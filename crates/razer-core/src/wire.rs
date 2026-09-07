// SPDX-License-Identifier: GPL-2.0-or-later
//! Wire layout from OpenRazer driver/razercommon.h: struct razer_report.
pub const HEADER_SIZE: usize = 8;
pub const ARGUMENT_CAPACITY: usize = 80;
pub const CHECKSUM_START: usize = 2;
pub const CHECKSUM_OFFSET: usize = HEADER_SIZE + ARGUMENT_CAPACITY;
pub const REPORT_SIZE: usize = CHECKSUM_OFFSET + 2;
pub const HID_REPORT_SIZE: usize = REPORT_SIZE + 1;
pub const COMMAND_ID_OFFSET: usize = HEADER_SIZE - 1;
pub const QUERY_FLAG: u8 = 0x80;

/// USB vendor ID assigned to Razer, from the upstream device declarations.
pub const RAZER_VENDOR_ID: u16 = 0x1532;
