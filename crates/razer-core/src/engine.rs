// SPDX-License-Identifier: GPL-2.0-or-later
//! Platform-independent transport contract and response validation.
use crate::wire::*;
pub trait Transport: Send {
    fn exchange(&mut self, request: &[u8], legacy: bool) -> Result<Vec<u8>, String>;
}
pub fn validate_response(request: &[u8], response: &[u8]) -> Result<(), String> {
    if response.len() != REPORT_SIZE || request.len() != REPORT_SIZE {
        return Err("报文长度必须为 90 字节".into());
    }
    if response[5] as usize > ARGUMENT_CAPACITY {
        return Err("响应参数过长".into());
    }
    // Match the request before trusting payload bytes: another controller may be active.
    if response[2..4] != request[2..4] || response[6..8] != request[6..8] {
        return Err("响应与请求不匹配，可能有其他程序同时控制设备".into());
    }
    if response[CHECKSUM_START..CHECKSUM_OFFSET]
        .iter()
        .fold(0, |crc, byte| crc ^ byte)
        != response[CHECKSUM_OFFSET]
    {
        return Err("响应校验失败".into());
    }
    match response[0] {
        2 => Ok(()),
        1 => Err("设备忙碌，结果尚未确认".into()),
        3 => Err("设备拒绝命令".into()),
        4 => Err("设备响应超时".into()),
        5 => Err("设备不支持此命令".into()),
        status => Err(format!("未知响应状态 {status}")),
    }
}
