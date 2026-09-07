// SPDX-License-Identifier: GPL-2.0-or-later
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;
#[derive(Clone, Serialize, Deserialize)]
pub struct Model {
    pub pid: u16,
    pub name: String,
    pub methods: Vec<String>,
    pub max_dpi: u32,
    pub min_dpi: u32,
    pub max_stages: u32,
    pub profile: Profile,
    pub poll_rates: Vec<u32>,
    pub matrix: Vec<u32>,
    pub dpi_list: Vec<u32>,
    pub attributes: Vec<String>,
    pub interface: i32,
    pub wait_us: u64,
}
pub fn models() -> &'static [Model] {
    static M: OnceLock<Vec<Model>> = OnceLock::new();
    M.get_or_init(|| serde_json::from_str(include_str!("catalog.json")).expect("embedded catalog"))
}
pub fn model(pid: u16) -> Option<&'static Model> {
    models().iter().find(|m| m.pid == pid)
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Attribute {
    pub name: String,
    pub read: bool,
    pub write: bool,
    pub excluded: bool,
}
pub fn attributes() -> &'static [Attribute] {
    static A: OnceLock<Vec<Attribute>> = OnceLock::new();
    A.get_or_init(|| serde_json::from_str(include_str!("../../../docs/attributes.json")).unwrap())
}

/// Wire variants derived from the pinned driver's recording transport.
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StateModel {
    Independent,
    LegacyPacket,
    CoupledDpiPoll,
}
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DpiRead {
    BytePair,
    WordPair,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Profile {
    pub state_model: StateModel,
    pub dpi_read: DpiRead,
    pub brightness_offset: Option<usize>,
    /// Upstream returns software state for these controls, not a hardware measurement.
    pub cached_attributes: Vec<String>,
}
#[derive(Deserialize)]
pub struct Limits {
    pub dpi: [u16; 2],
    pub idle: [u16; 2],
    pub low_battery: [u16; 2],
    pub max_stages: usize,
}
pub fn limits() -> &'static Limits {
    static LIMITS: OnceLock<Limits> = OnceLock::new();
    LIMITS.get_or_init(|| {
        serde_json::from_str(include_str!("limits.json")).expect("verified upstream limits")
    })
}
