// SPDX-License-Identifier: GPL-2.0-or-later
use crate::wire::*;
use crate::{
    catalog,
    engine::{validate_response, Transport},
};
use std::time::Duration;
pub struct HidTransport {
    pub device: hidapi::HidDevice,
    pub wait_us: u64,
}
impl Transport for HidTransport {
    fn exchange(&mut self, r: &[u8], legacy: bool) -> Result<Vec<u8>, String> {
        if legacy {
            return Err("此型号需要旧式 USB 控制传输".into());
        }
        let mut report = Vec::with_capacity(HID_REPORT_SIZE);
        report.push(0);
        report.extend_from_slice(r);
        // Only queries are replayed. A response mismatch can mean another app queried simultaneously.
        let attempts = if r[COMMAND_ID_OFFSET] & QUERY_FLAG != 0 {
            3
        } else {
            1
        };
        let mut last = String::new();
        for _ in 0..attempts {
            self.device
                .send_feature_report(&report)
                .map_err(|e| e.to_string())?;
            std::thread::sleep(Duration::from_micros(self.wait_us));
            let mut b = [0u8; HID_REPORT_SIZE];
            let n = self
                .device
                .get_feature_report(&mut b)
                .map_err(|e| e.to_string())?;
            if n != HID_REPORT_SIZE {
                last = format!("HID 返回 {n} 字节，预期包含 report ID 的 91 字节");
                continue;
            }
            match validate_response(r, &b[1..]) {
                Ok(()) => return Ok(b[1..].to_vec()),
                Err(e) => last = e,
            }
        }
        Err(last)
    }
}
pub struct UsbTransport {
    pub device: rusb::DeviceHandle<rusb::GlobalContext>,
    pub interface: u16,
    pub wait_us: u64,
}
impl Transport for UsbTransport {
    fn exchange(&mut self, r: &[u8], legacy: bool) -> Result<Vec<u8>, String> {
        let value = if legacy { 0x10 } else { 0x300 };
        let n = self
            .device
            .write_control(0x21, 9, value, self.interface, r, Duration::from_secs(2))
            .map_err(|e| format!("USB 控制传输失败：{e}"))?;
        if n != r.len() {
            return Err("USB 写入不完整".into());
        }
        std::thread::sleep(Duration::from_micros(if legacy {
            3000
        } else {
            self.wait_us
        }));
        if legacy {
            return Ok(vec![]);
        }
        let mut b = vec![0; REPORT_SIZE];
        let n = self
            .device
            .read_control(
                0xa1,
                1,
                0x300,
                self.interface,
                &mut b,
                Duration::from_secs(2),
            )
            .map_err(|e| e.to_string())?;
        b.truncate(n);
        Ok(b)
    }
}
fn open_native(d: &hidapi::DeviceInfo, api: &hidapi::HidApi) -> Result<Box<dyn Transport>, String> {
    let m = catalog::model(d.product_id()).ok_or("未知型号")?;
    if m.profile.state_model == catalog::StateModel::LegacyPacket || m.interface == 3 {
        // Explicit USB wIndex required. Never detach a kernel input driver.
        let candidates: Vec<_> = rusb::devices()
            .map_err(|e| e.to_string())?
            .iter()
            .filter(|device| {
                device.device_descriptor().is_ok_and(|desc| {
                    desc.vendor_id() == d.vendor_id() && desc.product_id() == d.product_id()
                })
            })
            .collect();
        // HID paths and libusb paths use different identifiers. Never guess between identical devices.
        let dev = if candidates.len() == 1 {
            candidates[0].open().map_err(|e| e.to_string())?
        } else {
            let serial = d
                .serial_number()
                .filter(|s| !s.is_empty())
                .ok_or("多只同型号设备无法唯一匹配 USB 控制接口")?;
            let mut matches = candidates.iter().filter_map(|device| {
                let desc = device.device_descriptor().ok()?;
                let handle = device.open().ok()?;
                (handle.read_serial_number_string_ascii(&desc).ok()?.as_str() == serial)
                    .then_some(handle)
            });
            let handle = matches.next().ok_or("无法匹配设备的 USB 序列号")?;
            if matches.next().is_some() {
                return Err("USB 序列号不唯一，无法安全选择设备".into());
            }
            handle
        };
        return Ok(Box::new(UsbTransport {
            device: dev,
            interface: m.interface as u16,
            wait_us: m.wait_us,
        }));
    }
    Ok(Box::new(HidTransport {
        device: d.open_device(api).map_err(|e| e.to_string())?,
        wait_us: m.wait_us,
    }))
}

// hidapi's macOS manager is bound to its initialization thread's CFRunLoop.
// A serial DispatchQueue or async executor does not provide that lifetime guarantee.
// Keep every native handle, enumeration and close on one process-local OS thread.
use std::{
    collections::HashMap,
    sync::{mpsc, OnceLock},
};
type Reply<T> = mpsc::Sender<Result<T, String>>;
enum IoRequest {
    Enumerate(Reply<Vec<hidapi::DeviceInfo>>),
    Open {
        info: hidapi::DeviceInfo,
        reply: Reply<()>,
    },
    Exchange {
        path: String,
        report: Vec<u8>,
        legacy: bool,
        reply: Reply<Vec<u8>>,
    },
    Close(String),
    #[cfg(test)]
    ThreadId(Reply<std::thread::ThreadId>),
}
struct Connection {
    transport: Box<dyn Transport>,
    owners: usize,
}
fn io_thread() -> Result<&'static mpsc::Sender<IoRequest>, String> {
    static WORKER: OnceLock<Result<mpsc::Sender<IoRequest>, String>> = OnceLock::new();
    WORKER
        .get_or_init(|| {
            let (sender, receiver) = mpsc::channel();
            std::thread::Builder::new()
                .name("razer.hid".into())
                .spawn(move || {
                    let mut api: Option<hidapi::HidApi> = None;
                    let mut connections: HashMap<String, Connection> = HashMap::new();
                    for request in receiver {
                        match request {
                            IoRequest::Enumerate(reply) => {
                                let result = (|| {
                                    if api.is_none() {
                                        api =
                                            Some(hidapi::HidApi::new().map_err(|e| e.to_string())?);
                                    }
                                    let api = api.as_mut().ok_or("HID 初始化失败")?;
                                    api.reset_devices().map_err(|e| e.to_string())?;
                                    api.add_devices(RAZER_VENDOR_ID, 0)
                                        .map_err(|e| e.to_string())?;
                                    let devices: Vec<_> = api.device_list().cloned().collect();
                                    connections.retain(|path, _| {
                                        devices
                                            .iter()
                                            .any(|d| d.path().to_string_lossy() == path.as_str())
                                    });
                                    Ok(devices)
                                })();
                                let _ = reply.send(result);
                            }
                            IoRequest::Open { info, reply } => {
                                let path = info.path().to_string_lossy().into_owned();
                                let result = if let Some(connection) = connections.get_mut(&path) {
                                    connection.owners += 1;
                                    Ok(())
                                } else {
                                    api.as_ref()
                                        .ok_or_else(|| "请先枚举设备".to_string())
                                        .and_then(|api| open_native(&info, api))
                                        .map(|transport| {
                                            connections.insert(
                                                path,
                                                Connection {
                                                    transport,
                                                    owners: 1,
                                                },
                                            );
                                        })
                                };
                                let _ = reply.send(result);
                            }
                            IoRequest::Exchange {
                                path,
                                report,
                                legacy,
                                reply,
                            } => {
                                let result = connections
                                    .get_mut(&path)
                                    .ok_or_else(|| "设备已断开".to_string())
                                    .and_then(|connection| {
                                        connection.transport.exchange(&report, legacy)
                                    });
                                let _ = reply.send(result);
                            }
                            IoRequest::Close(path) => {
                                if let Some(connection) = connections.get_mut(&path) {
                                    connection.owners -= 1;
                                    if connection.owners == 0 {
                                        connections.remove(&path);
                                    }
                                }
                            }
                            #[cfg(test)]
                            IoRequest::ThreadId(reply) => {
                                let _ = reply.send(Ok(std::thread::current().id()));
                            }
                        }
                    }
                })
                .map(|_| sender)
                .map_err(|e| e.to_string())
        })
        .as_ref()
        .map_err(Clone::clone)
}
fn request<T>(build: impl FnOnce(Reply<T>) -> IoRequest) -> Result<T, String> {
    let (reply, receiver) = mpsc::channel();
    io_thread()?
        .send(build(reply))
        .map_err(|_| "HID 工作线程已退出")?;
    receiver.recv().map_err(|_| "HID 工作线程未返回结果")?
}
pub fn enumerate() -> Result<Vec<hidapi::DeviceInfo>, String> {
    request(IoRequest::Enumerate)
}
pub fn open(info: &hidapi::DeviceInfo) -> Result<Box<dyn Transport>, String> {
    request(|reply| IoRequest::Open {
        info: info.clone(),
        reply,
    })?;
    Ok(Box::new(ConnectionProxy {
        path: info.path().to_string_lossy().into_owned(),
    }))
}
struct ConnectionProxy {
    path: String,
}
impl Transport for ConnectionProxy {
    fn exchange(&mut self, report: &[u8], legacy: bool) -> Result<Vec<u8>, String> {
        request(|reply| IoRequest::Exchange {
            path: self.path.clone(),
            report: report.into(),
            legacy,
            reply,
        })
    }
}
impl Drop for ConnectionProxy {
    fn drop(&mut self) {
        if let Ok(worker) = io_thread() {
            let _ = worker.send(IoRequest::Close(self.path.clone()));
        }
    }
}
#[cfg(test)]
#[test]
fn callers_on_different_threads_share_a_persistent_io_thread() {
    let expected = request(IoRequest::ThreadId).unwrap();
    for _ in 0..32 {
        let actual = std::thread::spawn(|| request(IoRequest::ThreadId).unwrap())
            .join()
            .unwrap();
        assert_eq!(actual, expected);
    }
    assert_ne!(expected, std::thread::current().id());
}
