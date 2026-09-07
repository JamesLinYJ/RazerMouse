// SPDX-License-Identifier: GPL-2.0-or-later
use crate::{
    backend,
    catalog::{self, Model},
    protocol::Session as ProtocolSession,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum Error {
    #[error("{message}")]
    Device { message: String },
}
fn err(s: impl ToString) -> Error {
    Error::Device {
        message: s.to_string(),
    }
}
#[derive(Clone, Serialize, Deserialize, uniffi::Record)]
pub struct DeviceInfo {
    pub id: String,
    pub name: String,
    pub pid: u16,
    pub connection: String,
    pub max_dpi: u32,
    pub min_dpi: u32,
    pub max_stages: u32,
    pub ranges: Vec<ControlRange>,
    pub readable_attributes: Vec<String>,
    pub cached_attributes: Vec<String>,
    pub poll_rates: Vec<u32>,
    pub attributes: Vec<String>,
    pub dpi_list: Vec<u32>,
    pub led_count: u32,
    pub tilt_supported: bool,
}
#[derive(Clone, Serialize, Deserialize, uniffi::Record)]
pub struct LegacyConfiguration {
    pub dpi: u32,
    pub poll_rate: u32,
    pub logo_on: bool,
    pub scroll_on: bool,
}
#[derive(Clone, Serialize, Deserialize, uniffi::Record)]
pub struct ControlRange {
    pub name: String,
    pub minimum: u32,
    pub maximum: u32,
}
fn control_range(name: &str) -> Option<ControlRange> {
    let limits = catalog::limits();
    let [minimum, maximum] = match name {
        "device_idle_time" => limits.idle,
        "charge_low_threshold" => limits.low_battery,
        n if n.contains("brightness") => [u8::MIN.into(), u8::MAX.into()],
        "scroll_mode" | "scroll_acceleration" | "scroll_smart_reel" => [0, 1],
        _ => return None,
    };
    Some(ControlRange {
        name: name.into(),
        minimum: minimum.into(),
        maximum: maximum.into(),
    })
}
#[derive(Clone, Serialize, Deserialize, uniffi::Record)]
pub struct DpiStage {
    pub x: u32,
    pub y: u32,
}
#[derive(Clone, Serialize, Deserialize, uniffi::Record)]
pub struct Snapshot {
    pub device: DeviceInfo,
    pub battery: Option<u32>,
    pub charging: Option<bool>,
    pub dpi: Option<DpiStage>,
    pub stages: Vec<DpiStage>,
    pub active_stage: Option<u32>,
    pub poll_rate: Option<u32>,
    pub idle_seconds: Option<u32>,
    pub low_battery: Option<u32>,
    pub firmware: Option<String>,
    pub errors: Vec<String>,
}
struct Session {
    info: DeviceInfo,
    context: Mutex<ProtocolSession>,
}
#[derive(uniffi::Object)]
pub struct Controller {
    sessions: Mutex<BTreeMap<String, Arc<Session>>>,
}
// nagahex.py uses a full-scale value of 6750 and rounds to two decimals before truncating.
const BYTE_DPI_FULL_SCALE: f64 = 6750.0;
fn byte_dpi(value: u32) -> u8 {
    ((f64::from(value).min(BYTE_DPI_FULL_SCALE) / BYTE_DPI_FULL_SCALE * f64::from(u8::MAX) * 100.0)
        .round()
        / 100.0) as u8
}
fn unscale_byte_dpi(value: u32) -> u32 {
    ((f64::from(value) / f64::from(u8::MAX) * BYTE_DPI_FULL_SCALE * 100.0).round() / 100.0) as u32
}
fn describe(d: &hidapi::DeviceInfo, m: &Model) -> DeviceInfo {
    DeviceInfo {
        id: d.path().to_string_lossy().into_owned(),
        name: m.name.clone(),
        pid: m.pid,
        connection: if m.name.contains("Bluetooth") {
            "蓝牙"
        } else if m.name.contains("Wireless") || m.name.contains("Receiver") {
            "无线接收器"
        } else {
            "USB"
        }
        .into(),
        max_dpi: m.max_dpi,
        min_dpi: m.min_dpi,
        max_stages: m.max_stages,
        ranges: m
            .attributes
            .iter()
            .filter_map(|n| control_range(n))
            .collect(),
        readable_attributes: m
            .attributes
            .iter()
            .filter(|n| {
                catalog::attributes()
                    .iter()
                    .any(|a| a.name == **n && a.read && !a.excluded)
            })
            .cloned()
            .collect(),
        cached_attributes: m.profile.cached_attributes.clone(),
        poll_rates: m.poll_rates.clone(),
        attributes: m
            .attributes
            .iter()
            .filter(|n| {
                catalog::attributes()
                    .iter()
                    .any(|a| a.name == **n && !a.excluded)
            })
            .cloned()
            .collect(),
        dpi_list: m.dpi_list.clone(),
        led_count: m.matrix.iter().product(),
        tilt_supported: m.attributes.iter().any(|name| name == "tilt_hwheel"),
    }
}
fn transact(s: &Session, name: &str, input: Option<&[u8]>) -> Result<Vec<u8>, Error> {
    if !s.info.attributes.iter().any(|a| a == name) {
        return Err(err("设备不支持此控制项"));
    }
    let a = catalog::attributes()
        .iter()
        .find(|a| a.name == name && !a.excluded)
        .ok_or_else(|| err("未知控制项"))?;
    if input.is_some() && !a.write || input.is_none() && !a.read {
        return Err(err("不支持此操作方向"));
    }
    if let Some(b) = input {
        validate_input(name, b, s.info.pid)?;
    }
    let mut protocol = s.context.lock().map_err(err)?;
    protocol.execute(name, input).map_err(err)
}
fn validate_input(name: &str, b: &[u8], pid: u16) -> Result<(), Error> {
    if b.len() > 512 {
        return Err(err("输入过长"));
    }
    let invalid = || err("参数长度或范围无效");
    match name {
        "dpi" => {
            if !matches!(b.len(), 1 | 2 | 4) {
                return Err(invalid());
            }
        }
        "dpi_stages" => {
            if b.len() < 5
                || (b.len() - 1) % 4 != 0
                || (b.len() - 1) / 4 > catalog::limits().max_stages
                || b[0] == 0
                || b[0] as usize > (b.len() - 1) / 4
            {
                return Err(invalid());
            }
        }
        "device_mode" => {
            if b.len() != 2 || !matches!(b[0], 0 | 3) || b[1] != 0 {
                return Err(invalid());
            }
        }
        "matrix_custom_frame" => {
            let m = catalog::model(pid).unwrap();
            let leds = m.matrix.iter().product::<u32>();
            let mut p = 0;
            while p < b.len() {
                if p + 3 > b.len() {
                    return Err(invalid());
                }
                let row = b[p];
                let first = b[p + 1];
                let last = b[p + 2];
                if row != 0 || last < first || last as u32 >= leds || last - first > 23 {
                    return Err(invalid());
                }
                p += 3 + (last - first + 1) as usize * 3;
                if p > b.len() {
                    return Err(invalid());
                }
            }
            if b.is_empty() {
                return Err(invalid());
            }
        }
        n if n.ends_with("reactive") => {
            if b.len() != 4 || !(1..=4).contains(&b[0]) {
                return Err(invalid());
            }
        }
        n if n.ends_with("static") || n.ends_with("blinking") || n == "charge_colour" => {
            if b.len() != 3 {
                return Err(invalid());
            }
        }
        n if n.ends_with("breath") => {
            if !matches!(b.len(), 1 | 3 | 6) {
                return Err(invalid());
            }
        }
        _ => {
            let text = std::str::from_utf8(b).map_err(err)?.trim();
            if text.parse::<u32>().is_err() {
                return Err(invalid());
            }
        }
    }
    Ok(())
}
impl Controller {
    fn session(&self, id: &str) -> Result<Arc<Session>, Error> {
        self.sessions
            .lock()
            .map_err(err)?
            .get(id)
            .cloned()
            .ok_or_else(|| err("鼠标已断开，请刷新设备"))
    }
    fn number(&self, id: &str, name: &str) -> Result<u32, Error> {
        self.read_text(id.into(), name.into())?
            .trim()
            .parse()
            .map_err(err)
    }
}
#[uniffi::export]
impl Controller {
    pub fn vendor_id(&self) -> u16 {
        crate::wire::RAZER_VENDOR_ID
    }
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            sessions: Mutex::new(BTreeMap::new()),
        })
    }
    pub fn devices(&self) -> Result<Vec<DeviceInfo>, Error> {
        let devices = backend::enumerate().map_err(err)?;
        let mut sessions = self.sessions.lock().map_err(err)?;
        let mut seen = vec![];
        let mut errors = vec![];
        for d in &devices {
            if d.vendor_id() != crate::wire::RAZER_VENDOR_ID {
                continue;
            }
            let Some(m) = catalog::model(d.product_id()) else {
                continue;
            };
            if !control_interface(m, d.interface_number(), d.usage_page(), d.usage()) {
                continue;
            }
            let info = describe(d, m);
            seen.push(info.id.clone());
            if !sessions.contains_key(&info.id) {
                match backend::open(d) {
                    Ok(t) => {
                        sessions.insert(
                            info.id.clone(),
                            Arc::new(Session {
                                info,
                                context: Mutex::new(ProtocolSession::new(m.pid, t)),
                            }),
                        );
                    }
                    Err(e) => errors.push(e),
                }
            }
        }
        sessions.retain(|id, _| seen.contains(id));
        if sessions.is_empty() && !errors.is_empty() {
            return Err(err(errors.join("；")));
        }
        Ok(sessions.values().map(|s| s.info.clone()).collect())
    }
    pub fn read_control(&self, id: String, name: String) -> Result<Vec<u8>, Error> {
        transact(self.session(&id)?.as_ref(), &name, None)
    }
    pub fn read_text(&self, id: String, name: String) -> Result<String, Error> {
        let bytes = self.read_control(id, name.clone())?;
        if name == "device_mode" {
            return match bytes.as_slice() {
                [mode, _parameter] => Ok(mode.to_string()),
                _ => Err(err("设备模式响应长度无效")),
            };
        }
        Ok(String::from_utf8_lossy(&bytes).trim().into())
    }
    pub fn write_control(&self, id: String, name: String, payload: Vec<u8>) -> Result<(), Error> {
        let s = self.session(&id)?;
        transact(&s, &name, Some(&payload))?;
        Ok(())
    }
    pub fn set_number(&self, id: String, name: String, value: u32) -> Result<String, Error> {
        let s = self.session(&id)?;
        match name.as_str() {
            "poll_rate" => {
                if !s.info.poll_rates.contains(&value) {
                    return Err(err("不支持的回报率"));
                }
            }
            _ => {}
        }
        if let Some(range) = control_range(&name) {
            if !(range.minimum..=range.maximum).contains(&value) {
                return Err(err(format!(
                    "{} 需在 {}–{} 范围内",
                    name, range.minimum, range.maximum
                )));
            }
        }
        self.write_control(id.clone(), name.clone(), value.to_string().into_bytes())?;
        if catalog::attributes()
            .iter()
            .any(|a| a.name == name && a.read)
        {
            let actual = self.read_text(id, name)?;
            if actual.parse::<u32>().ok() != Some(value) {
                return Err(err(format!("设备返回 {actual}，与设置值 {value} 不一致")));
            }
            Ok(actual)
        } else {
            Ok("已发送".into())
        }
    }
    /// Supplies every coupled field for devices without hardware readback.
    /// Success means sent; it must not be presented as a hardware measurement.
    pub fn configure_legacy(&self, id: String, settings: LegacyConfiguration) -> Result<(), Error> {
        let session = self.session(&id)?;
        let model = catalog::model(session.info.pid).unwrap();
        if !(model.min_dpi..=model.max_dpi).contains(&settings.dpi)
            || !model.poll_rates.contains(&settings.poll_rate)
            || (!model.dpi_list.is_empty() && !model.dpi_list.contains(&settings.dpi))
        {
            return Err(err("请选择设备支持的 DPI 与回报率"));
        }
        let dpi = if model.profile.state_model == catalog::StateModel::CoupledDpiPoll {
            byte_dpi(settings.dpi) as u16
        } else {
            settings.dpi as u16
        };
        let mut protocol = session.context.lock().map_err(err)?;
        protocol
            .configure_legacy(
                dpi,
                settings.poll_rate as u16,
                settings.logo_on,
                settings.scroll_on,
            )
            .map_err(err)
    }
    pub fn set_dpi(&self, id: String, x: u32, y: u32) -> Result<DpiStage, Error> {
        let s = self.session(&id)?;
        let m = catalog::model(s.info.pid).unwrap();
        if x < m.min_dpi || y < m.min_dpi || x > m.max_dpi || y > m.max_dpi {
            return Err(err(format!("DPI 需在 {}–{} 范围内", m.min_dpi, m.max_dpi)));
        }
        let b = if !m.dpi_list.is_empty() {
            if !m.dpi_list.contains(&x) || x != y {
                return Err(err("请选择设备支持的固定 DPI"));
            }
            (x as u16).to_be_bytes().to_vec()
        } else if m.methods.iter().any(|m| m == "set_dpi_xy_byte") {
            vec![byte_dpi(x), byte_dpi(y)]
        } else {
            [(x as u16).to_be_bytes(), (y as u16).to_be_bytes()].concat()
        };
        self.write_control(id.clone(), "dpi".into(), b)?;
        let actual = self.dpi(id)?;
        let expected = if m.methods.iter().any(|m| m == "set_dpi_xy_byte") {
            DpiStage {
                x: unscale_byte_dpi(byte_dpi(x).into()),
                y: unscale_byte_dpi(byte_dpi(y).into()),
            }
        } else {
            DpiStage { x, y }
        };
        if actual.x != expected.x || actual.y != expected.y {
            return Err(err(format!(
                "DPI 回读为 {} × {}，与设置不一致",
                actual.x, actual.y
            )));
        }
        Ok(actual)
    }
    pub fn dpi(&self, id: String) -> Result<DpiStage, Error> {
        let s = self.session(&id)?;
        let m = catalog::model(s.info.pid).unwrap();
        let text = self.read_text(id, "dpi".into())?;
        let nums = text
            .split(':')
            .map(str::parse::<u32>)
            .collect::<Result<Vec<_>, _>>()
            .map_err(err)?;
        let x = *nums.first().ok_or_else(|| err("DPI 响应为空"))?;
        let y = *nums.get(1).unwrap_or(&x);
        let scale = |v| {
            if m.methods.iter().any(|m| m == "get_dpi_xy_byte") {
                unscale_byte_dpi(v)
            } else {
                v
            }
        };
        Ok(DpiStage {
            x: scale(x),
            y: scale(y),
        })
    }
    pub fn set_stages(&self, id: String, stages: Vec<DpiStage>, active: u32) -> Result<(), Error> {
        let s = self.session(&id)?;
        if stages.is_empty()
            || stages.len() > s.info.max_stages as usize
            || active == 0
            || active as usize > stages.len()
        {
            return Err(err("DPI 档位数量或选中档位无效"));
        }
        let mut b = vec![active as u8];
        for d in &stages {
            if d.x < s.info.min_dpi
                || d.y < s.info.min_dpi
                || d.x > s.info.max_dpi
                || d.y > s.info.max_dpi
            {
                return Err(err("DPI 档位超出范围"));
            }
            b.extend_from_slice(&(d.x as u16).to_be_bytes());
            b.extend_from_slice(&(d.y as u16).to_be_bytes());
        }
        self.write_control(id.clone(), "dpi_stages".into(), b.clone())?;
        let got = self.read_control(id, "dpi_stages".into())?;
        if got != b {
            return Err(err("DPI 档位写入后回读不一致"));
        }
        Ok(())
    }
    pub fn snapshot(&self, id: String) -> Result<Snapshot, Error> {
        let s = self.session(&id)?;
        let mut out = Snapshot {
            device: s.info.clone(),
            battery: None,
            charging: None,
            dpi: None,
            stages: vec![],
            active_stage: None,
            poll_rate: None,
            idle_seconds: None,
            low_battery: None,
            firmware: None,
            errors: vec![],
        };
        for n in [
            "charge_level",
            "charge_status",
            "poll_rate",
            "device_idle_time",
            "charge_low_threshold",
        ] {
            if !s.info.attributes.iter().any(|x| x == n) {
                continue;
            }
            match self.number(&id, n) {
                Ok(v) => match n {
                    "charge_level" => out.battery = Some((v * 100 + 127) / 255),
                    "charge_status" => out.charging = Some(v == 1),
                    "poll_rate" => out.poll_rate = Some(v),
                    "device_idle_time" => out.idle_seconds = Some(v),
                    _ => out.low_battery = Some(v),
                },
                Err(e) => out.errors.push(format!("{n}: {e}")),
            }
        }
        if s.info.attributes.contains(&"dpi".into()) {
            match self.dpi(id.clone()) {
                Ok(d) => out.dpi = Some(d),
                Err(e) => out.errors.push(e.to_string()),
            }
        }
        if s.info.attributes.contains(&"dpi_stages".into()) {
            match self.read_control(id.clone(), "dpi_stages".into()) {
                Ok(b) if !b.is_empty() && (b.len() - 1) % 4 == 0 => {
                    out.active_stage = Some(b[0] as u32);
                    out.stages = b[1..]
                        .chunks_exact(4)
                        .map(|b| DpiStage {
                            x: u16::from_be_bytes([b[0], b[1]]) as u32,
                            y: u16::from_be_bytes([b[2], b[3]]) as u32,
                        })
                        .collect()
                }
                Ok(_) => out.errors.push("DPI 档位响应无效".into()),
                Err(e) => out.errors.push(e.to_string()),
            }
        }
        out.firmware = self.read_text(id, "firmware_version".into()).ok();
        Ok(out)
    }
    pub fn catalog_json(&self) -> String {
        serde_json::to_string(catalog::models()).unwrap()
    }
}

fn control_interface(model: &Model, interface: i32, usage_page: u16, usage: u16) -> bool {
    if usage_page != 1 || usage != 2 {
        return false;
    }
    // USB control-transfer models select wIndex when opening rusb; their mouse HID
    // interface is only used to identify the physical device. Native HID models
    // must use the upstream control interface, not another mouse usage collection.
    let uses_usb_control =
        model.profile.state_model == catalog::StateModel::LegacyPacket || model.interface == 3;
    uses_usb_control || interface < 0 || interface == i32::from(model.interface)
}

#[cfg(test)]
mod interface_tests {
    use super::*;
    #[test]
    fn composite_receiver_mouse_usages_do_not_become_duplicate_devices() {
        for model in catalog::models() {
            if model.interface == 0
                && model.profile.state_model != catalog::StateModel::LegacyPacket
            {
                assert!(control_interface(model, 0, 1, 2));
                assert!(!control_interface(model, 1, 1, 2));
                assert!(!control_interface(model, 0, 1, 6));
            }
        }
    }
}
