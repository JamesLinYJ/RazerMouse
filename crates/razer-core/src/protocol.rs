// SPDX-License-Identifier: GPL-2.0-or-later
//! Safe, data-driven Razer wire protocol. No C pointers or translated C control flow.
//! Model-specific layouts are data; framing, parameters, sequencing and decoding are Rust.
use crate::wire::*;
use crate::{
    catalog::{self, DpiRead, StateModel},
    engine::Transport,
};
use serde::Deserialize;
use std::{collections::HashMap, sync::OnceLock};

#[derive(Debug, thiserror::Error)]
pub enum ProtocolError {
    #[error("设备不支持此命令或参数形式")]
    Unsupported,
    #[error("参数无效：{0}")]
    Invalid(&'static str),
    #[error("设备通信失败：{0}")]
    Transport(String),
    #[error("响应无效：{0}")]
    Response(String),
}
pub type Result<T> = std::result::Result<T, ProtocolError>;

#[derive(Clone, Debug)]
pub struct Report {
    header: [u8; HEADER_SIZE],
    payload: [u8; ARGUMENT_CAPACITY],
    reserved: u8,
}
impl Report {
    pub(crate) fn from_template(bytes: &[u8]) -> Result<Self> {
        if bytes.len() != REPORT_SIZE {
            return Err(ProtocolError::Invalid("报文长度"));
        }
        let header = bytes
            .get(..HEADER_SIZE)
            .and_then(|s| s.try_into().ok())
            .ok_or(ProtocolError::Invalid("报文头"))?;
        let payload = bytes
            .get(HEADER_SIZE..CHECKSUM_OFFSET)
            .and_then(|s| s.try_into().ok())
            .ok_or(ProtocolError::Invalid("报文参数"))?;
        Ok(Self {
            header,
            payload,
            reserved: bytes[REPORT_SIZE - 1],
        })
    }
    pub fn encode(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(REPORT_SIZE);
        bytes.extend_from_slice(&self.header);
        bytes.extend_from_slice(&self.payload);
        bytes.push(
            bytes[CHECKSUM_START..CHECKSUM_OFFSET]
                .iter()
                .fold(0, |crc, b| crc ^ b),
        );
        bytes.push(self.reserved);
        bytes
    }
    fn response(request: &Self, bytes: &[u8]) -> Result<Self> {
        crate::engine::validate_response(&request.encode(), bytes)
            .map_err(ProtocolError::Response)?;
        Self::from_template(bytes)
    }
    fn word(&self, offset: usize) -> Result<u16> {
        self.payload
            .get(offset..offset + 2)
            .map(|b| u16::from_be_bytes([b[0], b[1]]))
            .ok_or(ProtocolError::Invalid("16 位参数越界"))
    }
}

#[derive(Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum ValueSource {
    Byte { input: usize },
    Map { input: usize, values: Vec<u8> },
    Low,
    High,
    IdleLow,
    IdleHigh,
    ScalarMap { values: Vec<u8> },
}
#[derive(Clone, Deserialize)]
struct Patch {
    frame: usize,
    offset: usize,
    #[serde(flatten)]
    source: ValueSource,
}
#[derive(Clone, Deserialize)]
struct Recipe {
    frames: Vec<Vec<u8>>,
    patches: Vec<Patch>,
    #[serde(default)]
    expected: Vec<u8>,
}
#[derive(Deserialize)]
struct WireCatalog {
    recipes: Vec<Recipe>,
    routes: Vec<(u16, String, bool, String, usize)>,
}
struct Layouts {
    recipes: Vec<Recipe>,
    routes: HashMap<(u16, String, bool, String), usize>,
}
fn layouts() -> &'static Layouts {
    static TABLE: OnceLock<Layouts> = OnceLock::new();
    TABLE.get_or_init(|| {
        let data: WireCatalog =
            serde_json::from_str(include_str!("recipes.json")).expect("verified wire layouts");
        Layouts {
            recipes: data.recipes,
            routes: data
                .routes
                .into_iter()
                .map(|(p, n, w, v, i)| ((p, n, w, v), i))
                .collect(),
        }
    })
}
fn recipe(pid: u16, name: &str, write: bool, variant: &str) -> Result<&'static Recipe> {
    let l = layouts();
    l.routes
        .get(&(pid, name.into(), write, variant.into()))
        .map(|i| &l.recipes[*i])
        .ok_or(ProtocolError::Unsupported)
}
fn integer(input: &[u8]) -> Result<u16> {
    std::str::from_utf8(input)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .ok_or(ProtocolError::Invalid("整数"))
}
fn binary(name: &str) -> bool {
    name == "dpi"
        || name == "device_mode"
        || name == "charge_colour"
        || name.ends_with("static")
        || name.ends_with("reactive")
        || name.ends_with("breath")
        || name.ends_with("blinking")
}
impl Recipe {
    fn instantiate(&self, input: &[u8], numeric: bool) -> Result<Vec<Vec<u8>>> {
        let scalar = if numeric { integer(input)? } else { 0 };
        let mut frames = self.frames.clone();
        for patch in &self.patches {
            let byte = |i: usize| {
                input
                    .get(i)
                    .copied()
                    .ok_or(ProtocolError::Invalid("缺少参数"))
            };
            let lookup = |map: &[u8], i: usize| {
                map.get(i)
                    .copied()
                    .ok_or(ProtocolError::Invalid("参数范围"))
            };
            let value = match &patch.source {
                ValueSource::Byte { input } => byte(*input)?,
                ValueSource::Map { input, values } => lookup(values, byte(*input)? as usize)?,
                ValueSource::Low => scalar as u8,
                ValueSource::High => (scalar >> 8) as u8,
                ValueSource::IdleLow => {
                    scalar.clamp(catalog::limits().idle[0], catalog::limits().idle[1]) as u8
                }
                ValueSource::IdleHigh => {
                    (scalar.clamp(catalog::limits().idle[0], catalog::limits().idle[1]) >> 8) as u8
                }
                ValueSource::ScalarMap { values } => lookup(values, scalar as usize)?,
            };
            *frames
                .get_mut(patch.frame)
                .and_then(|f| f.get_mut(patch.offset))
                .ok_or(ProtocolError::Invalid("布局越界"))? = value;
        }
        Ok(frames)
    }
}

#[derive(Clone)]
struct LegacyState {
    poll: u16,
    dpi: u16,
    leds: u8,
    profile: u8,
}
impl LegacyState {
    fn encode(&self) -> [u8; 4] {
        // razermouse_driver.c: deathadder3_5g polling and sensitivity encodings.
        let poll = match self.poll {
            1000 => 1,
            125 => 3,
            _ => 2,
        };
        let dpi = match self.dpi {
            450 => 4,
            900 => 3,
            1800 => 2,
            _ => 1,
        };
        [poll, dpi, self.profile, self.leds]
    }
}
pub struct Session {
    pid: u16,
    transport: Box<dyn Transport>,
    legacy: Option<LegacyState>,
    orochi_dpi: Option<u8>,
    orochi_leds: Option<u8>,
    orochi_poll: Option<u16>,
    profile: &'static catalog::Profile,
}
impl Session {
    pub fn new(pid: u16, transport: Box<dyn Transport>) -> Self {
        Self {
            pid,
            transport,
            legacy: None,
            orochi_dpi: None,
            orochi_leds: None,
            orochi_poll: None,
            profile: &catalog::model(pid)
                .expect("catalog checked before opening session")
                .profile,
        }
    }
    /// Older protocols write several settings together and cannot query them.
    /// Every field must therefore be supplied by the caller; there are no initial defaults.
    pub fn configure_legacy(
        &mut self,
        dpi: u16,
        poll: u16,
        logo: bool,
        scroll: bool,
    ) -> Result<()> {
        match self.profile.state_model {
            StateModel::Independent => Err(ProtocolError::Unsupported),
            StateModel::LegacyPacket => {
                // The driver's legacy packet selects the single supported profile.
                let next = LegacyState {
                    dpi,
                    poll,
                    profile: 1,
                    leds: u8::from(logo) | (u8::from(scroll) << 1),
                };
                self.legacy = None;
                self.transport
                    .exchange(&next.encode(), true)
                    .map_err(ProtocolError::Transport)?;
                self.legacy = Some(next);
                Ok(())
            }
            StateModel::CoupledDpiPoll => {
                let mut request = Report::from_template(
                    &recipe(self.pid, "poll_rate", true, &poll.to_string())?.frames[0],
                )?;
                let dpi = u8::try_from(dpi).map_err(|_| ProtocolError::Invalid("字节 DPI 越界"))?;
                request.payload[3] = dpi.clamp(0x15, 0x9c);
                request.payload[4] = request.payload[3];
                let leds = u8::from(scroll) | (u8::from(logo) << 1);
                let mut lighting = Report::from_template(
                    &recipe(self.pid, "logo_matrix_effect_on", true, "scalar")?.frames[0],
                )?;
                lighting.payload[1] = leds;
                // Invalidate prior knowledge before a multi-report operation which can partially succeed.
                self.orochi_dpi = None;
                self.orochi_poll = None;
                self.orochi_leds = None;
                self.exchange(&request)?;
                self.exchange(&lighting)?;
                self.orochi_dpi = Some(dpi);
                self.orochi_poll = Some(poll);
                self.orochi_leds = Some(leds);
                Ok(())
            }
        }
    }
    #[cfg(test)]
    pub fn seed_reference_state(
        &mut self,
        poll: u16,
        dpi: u16,
        leds: u8,
        profile: u8,
        byte_dpi: u8,
    ) {
        self.legacy = Some(LegacyState {
            poll,
            dpi,
            leds,
            profile,
        });
        self.orochi_poll = Some(poll);
        self.orochi_dpi = Some(byte_dpi);
        self.orochi_leds = Some(leds);
    }
    pub fn execute(&mut self, name: &str, input: Option<&[u8]>) -> Result<Vec<u8>> {
        if self.profile.state_model == StateModel::LegacyPacket {
            return self.deathadder_legacy(name, input);
        }
        if self.profile.state_model == StateModel::CoupledDpiPoll && input.is_none() {
            match name {
                "dpi" => {
                    let dpi = self
                        .orochi_dpi
                        .ok_or(ProtocolError::Invalid("设备不能回读 DPI，尚未在此会话设置"))?;
                    return Ok(format!("{dpi}:{dpi}\n").into_bytes());
                }
                "poll_rate" => {
                    let poll = self.orochi_poll.ok_or(ProtocolError::Invalid(
                        "设备不能回读回报率，尚未在此会话设置",
                    ))?;
                    return Ok(format!("{poll}\n").into_bytes());
                }
                _ => {}
            }
        }
        match input {
            None => self.read(name),
            Some(input) => {
                if matches!(
                    name,
                    "scroll_mode" | "scroll_acceleration" | "scroll_smart_reel"
                ) && integer(input)? > 1
                {
                    return Err(ProtocolError::Invalid("开关只接受 0/1"));
                }
                let frames = match name {
                    "dpi_stages" => self.stages(input)?,
                    "matrix_custom_frame" => self.colors(input)?,
                    _ => {
                        let variant = if name == "poll_rate" {
                            integer(input)?.to_string()
                        } else if binary(name) {
                            input.len().to_string()
                        } else {
                            "scalar".into()
                        };
                        let mut bytes = input.to_vec();
                        if name == "dpi" && input.len() == 4 {
                            for word in bytes.chunks_exact_mut(2) {
                                let v = u16::from_be_bytes([word[0], word[1]])
                                    .clamp(catalog::limits().dpi[0], catalog::limits().dpi[1]);
                                word.copy_from_slice(&v.to_be_bytes());
                            }
                        }
                        recipe(self.pid, name, true, &variant)?
                            .instantiate(&bytes, !binary(name) && name != "poll_rate")?
                    }
                };
                let mut new_dpi = self.orochi_dpi;
                let mut new_leds = self.orochi_leds;
                let mut new_poll = self.orochi_poll;
                for bytes in frames {
                    let mut request = Report::from_template(&bytes)?;
                    if self.profile.state_model == StateModel::CoupledDpiPoll {
                        match name {
                            "dpi" => {
                                new_dpi =
                                    Some(*input.first().ok_or(ProtocolError::Invalid("DPI"))?);
                                request.payload[1] =
                                    match self.orochi_poll.ok_or(ProtocolError::Invalid(
                                        "此设备需要先明确提供完整 DPI 与回报率配置",
                                    ))? {
                                        1000 => 1,
                                        125 => 8,
                                        _ => 2,
                                    };
                            }
                            "poll_rate" => {
                                new_poll = Some(integer(input)?);
                                request.payload[3] = self
                                    .orochi_dpi
                                    .ok_or(ProtocolError::Invalid(
                                        "此设备需要先明确提供完整 DPI 与回报率配置",
                                    ))?
                                    .clamp(0x15, 0x9c);
                                request.payload[4] = request.payload[3];
                            }
                            n if n.ends_with("_on") || n.ends_with("_none") => {
                                let mask = if n.starts_with("logo") { 2 } else { 1 };
                                let previous = new_leds.ok_or(ProtocolError::Invalid(
                                    "此设备需要明确提供所有灯区状态",
                                ))?;
                                let leds = if n.ends_with("_on") {
                                    previous | mask
                                } else {
                                    previous & !mask
                                };
                                new_leds = Some(leds);
                                request.payload[1] = leds;
                            }
                            _ => {}
                        }
                    }
                    if let Err(error) = self.exchange(&request) {
                        self.orochi_dpi = None;
                        self.orochi_leds = None;
                        self.orochi_poll = None;
                        return Err(error);
                    }
                }
                self.orochi_dpi = new_dpi;
                self.orochi_leds = new_leds;
                self.orochi_poll = new_poll;
                Ok(vec![])
            }
        }
    }
    fn exchange(&mut self, request: &Report) -> Result<Report> {
        let bytes = self
            .transport
            .exchange(&request.encode(), false)
            .map_err(ProtocolError::Transport)?;
        Report::response(request, &bytes)
    }
    fn read(&mut self, name: &str) -> Result<Vec<u8>> {
        let spec = recipe(self.pid, name, false, "read")?;
        let mut last = None;
        for bytes in &spec.frames {
            let request = Report::from_template(bytes)?;
            last = Some(self.exchange(&request)?);
        }
        let Some(response) = last else {
            if self.profile.cached_attributes.iter().any(|n| n == name) {
                return Err(ProtocolError::Invalid("此属性没有硬件读取接口"));
            }
            return Ok(spec.expected.clone());
        };
        let a = &response.payload;
        let text = |n: u32| format!("{n}\n").into_bytes();
        Ok(match name {
            "firmware_version" => format!("v{}.{}\n", a[0], a[1]).into_bytes(),
            "device_serial" => {
                let mut s = a[..22]
                    .iter()
                    .copied()
                    .take_while(|b| *b != 0)
                    .collect::<Vec<_>>();
                s.push(b'\n');
                s
            }
            "device_mode" => a[..2].to_vec(),
            "charge_level"
            | "charge_status"
            | "scroll_mode"
            | "scroll_acceleration"
            | "scroll_smart_reel" => text(a[1] as u32),
            "charge_low_threshold" => text(a[0] as u32),
            "device_idle_time" => text(response.word(0)? as u32),
            "poll_rate" => {
                let (v, base) = if response.header[7] == 0xc0 {
                    (a[1], 8000)
                } else {
                    (a[0], 1000)
                };
                let rate = if matches!(v, 1 | 2 | 8) || (base == 8000 && matches!(v, 4 | 16 | 64)) {
                    base / v as u32
                } else {
                    0
                };
                text(rate)
            }
            "dpi" => {
                let (x, y) = if self.profile.dpi_read == DpiRead::BytePair {
                    (a[0] as u16, a[1] as u16)
                } else {
                    (response.word(1)?, response.word(3)?)
                };
                format!("{x}:{y}\n").into_bytes()
            }
            "dpi_stages" => {
                let count = a[2] as usize;
                let size = response.header[5] as usize;
                if count > catalog::limits().max_stages || size < 3 || count * 7 + 3 > size {
                    return Err(ProtocolError::Response("DPI 档位数量或长度无效".into()));
                }
                let mut data = vec![a[1]];
                for i in 0..count {
                    data.extend_from_slice(&a[4 + i * 7..8 + i * 7]);
                }
                data
            }
            "matrix_brightness" => text(
                a[self
                    .profile
                    .brightness_offset
                    .ok_or(ProtocolError::Unsupported)?] as u32,
            ),
            n if n.ends_with("led_brightness") => text(a[2] as u32),
            _ => return Err(ProtocolError::Unsupported),
        })
    }
    fn stages(&self, input: &[u8]) -> Result<Vec<Vec<u8>>> {
        let count = input.len().saturating_sub(1) / 4;
        if !(1..=catalog::limits().max_stages).contains(&count)
            || input.len() != 1 + 4 * count
            || input[0] == 0
            || input[0] as usize > count
        {
            return Err(ProtocolError::Invalid("DPI 档位"));
        }
        let spec = recipe(self.pid, "dpi_stages", true, "dynamic")?;
        let mut report = Report::from_template(&spec.frames[0])?;
        report.payload[1] = input[0];
        report.payload[2] = count as u8;
        report.payload[3..].fill(0);
        for (i, xy) in input[1..].chunks_exact(4).enumerate() {
            let start = 3 + 7 * i;
            report.payload[start] = i as u8;
            report.payload[start + 1..start + 5].copy_from_slice(xy);
        }
        Ok(vec![report.encode()])
    }
    fn colors(&self, input: &[u8]) -> Result<Vec<Vec<u8>>> {
        let spec = recipe(self.pid, "matrix_custom_frame", true, "dynamic")?;
        let template = Report::from_template(&spec.frames[0])?;
        let mut result = vec![];
        let mut remaining = input;
        while !remaining.is_empty() {
            let header = remaining
                .get(..3)
                .ok_or(ProtocolError::Invalid("RGB 帧头"))?;
            let (row, start, end) = (header[0], header[1], header[2]);
            if row != 0 || start > end {
                return Err(ProtocolError::Invalid("RGB 区域"));
            }
            let length = (end - start + 1) as usize * 3;
            let colors = remaining
                .get(3..3 + length)
                .ok_or(ProtocolError::Invalid("RGB 数据不足"))?;
            let mut r = template.clone();
            let offset = match (r.header[6], r.header[7]) {
                (3, 0x0b) => {
                    r.payload[1..4].copy_from_slice(&[row, start, end]);
                    4
                }
                (0x0f, 3) => {
                    r.payload[..5].copy_from_slice(&[0, 0, row, start, end]);
                    5
                }
                (3, 0x0c) => {
                    r.payload[..2].copy_from_slice(&[start, end]);
                    2
                }
                _ => return Err(ProtocolError::Unsupported),
            };
            if r.header[6] == 0x0f && r.header[5] == 8 {
                r.header[5] = (length + 5) as u8;
            }
            r.payload[offset..].fill(0);
            r.payload
                .get_mut(offset..offset + length)
                .ok_or(ProtocolError::Invalid("RGB 行过长"))?
                .copy_from_slice(colors);
            result.push(r.encode());
            remaining = &remaining[3 + length..];
        }
        Ok(result)
    }
    fn deathadder_legacy(&mut self, name: &str, input: Option<&[u8]>) -> Result<Vec<u8>> {
        if name == "device_type" {
            return self.read(name);
        }
        let known = self.legacy.as_ref().ok_or(ProtocolError::Invalid(
            "旧式设备不能回读设置，请明确提供完整配置",
        ))?;
        let Some(input) = input else {
            return match name {
                "dpi" => Ok(format!("{}\n", known.dpi).into_bytes()),
                "poll_rate" => Ok(format!("{}\n", known.poll).into_bytes()),
                _ => Err(ProtocolError::Invalid("此属性没有硬件读取接口")),
            };
        };
        let mut next = known.clone();
        match name {
            "dpi" => {
                let bytes: [u8; 2] = input
                    .try_into()
                    .map_err(|_| ProtocolError::Invalid("DPI"))?;
                next.dpi = match u16::from_be_bytes(bytes) {
                    v @ (450 | 900 | 1800) => v,
                    _ => 3500,
                };
            }
            "poll_rate" => {
                next.poll = match integer(input)? {
                    v @ (125 | 1000) => v,
                    _ => 500,
                };
            }
            n if n.ends_with("_on") || n.ends_with("_none") => {
                let mask = if n.starts_with("logo") { 1 } else { 2 };
                next.leds = if n.ends_with("_on") {
                    next.leds | mask
                } else {
                    next.leds & !mask
                };
            }
            "device_mode" => return Ok(vec![]),
            _ => return Err(ProtocolError::Unsupported),
        }
        let bytes = next.encode();
        self.legacy = None;
        self.transport
            .exchange(&bytes, true)
            .map_err(ProtocolError::Transport)?;
        self.legacy = Some(next);
        Ok(vec![])
    }
}
