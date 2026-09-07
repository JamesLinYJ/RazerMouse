// SPDX-License-Identifier: GPL-2.0-or-later
mod backend;
pub mod catalog;
mod controller;
pub use controller::*;
mod engine;
mod protocol;
uniffi::setup_scaffolding!();
#[cfg(test)]
mod tests;

mod wire;
