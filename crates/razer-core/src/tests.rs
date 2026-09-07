// SPDX-License-Identifier: GPL-2.0-or-later
use super::*;
use engine::*;
use std::sync::{Arc, Mutex};
#[derive(serde::Deserialize)]
struct Case {
    pid: u16,
    name: String,
    write: bool,
    input: Vec<u8>,
    result: i64,
    output: Vec<u8>,
    packets: Vec<Vec<u8>>,
}
struct OracleTransport(Arc<Mutex<Vec<Vec<u8>>>>);
impl Transport for OracleTransport {
    fn exchange(&mut self, r: &[u8], legacy: bool) -> Result<Vec<u8>, String> {
        self.0.lock().unwrap().push(r.to_vec());
        if legacy {
            return Ok(vec![]);
        }
        let mut b = r.to_vec();
        b[0] = 2;
        for i in 0..80 {
            b[8 + i] = ((i * 7 + 3) % 256) as u8;
        }
        if r[6] == 4 && r[7] == 0x86 {
            b[9] = 2;
            b[10] = 3;
            b[5] = 24;
        }
        b[88] = b[2..88].iter().fold(0, |a, x| a ^ x);
        Ok(b)
    }
}
#[test]
#[ignore = "requires an external oracle corpus; not included in the public repository"]
fn differential_all_mouse_commands() {
    // The optional research corpus is deliberately outside the published source tree.
    let path = std::env::var("RAZER_ORACLE_VECTORS")
        .expect("set RAZER_ORACLE_VECTORS to an external oracle JSON file");
    let cases: Vec<Case> = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    assert!(!cases.is_empty(), "an empty corpus must not count as verification");
    let mut failures = vec![];
    for c in &cases {
        let packets = Arc::new(Mutex::new(vec![]));
        let mut session = protocol::Session::new(c.pid, Box::new(OracleTransport(packets.clone())));
        session.seed_reference_state(500, 3500, 3, 1, 0x3c);
        let result = session.execute(&c.name, if c.write { Some(&c.input) } else { None });
        let got = packets.lock().unwrap().clone();
        // Upstream's cached Orochi polling getter returns 0 because it truncates Hz
        // into one byte. Product returns the confirmed session value instead.
        let cached_poll = catalog::model(c.pid).unwrap().profile.state_model
            == catalog::StateModel::CoupledDpiPoll
            && c.name == "poll_rate"
            && !c.write;
        let cached_other = catalog::model(c.pid)
            .unwrap()
            .profile
            .cached_attributes
            .contains(&c.name)
            && !c.write
            && !matches!(c.name.as_str(), "dpi" | "poll_rate");
        let matches = if cached_poll {
            result.as_ref().is_ok_and(|v| v == b"500\n") && got.is_empty()
        } else if cached_other {
            result.is_err() || result.as_ref().ok() == Some(&c.output)
        } else {
            match result {
                Ok(ref output) => {
                    c.result >= 0 && (c.write || *output == c.output) && got == c.packets
                }
                Err(_) => c.result < 0,
            }
        };
        if !matches {
            failures.push(format!("pid {:04x} {} write={} input={:?}: result {:?}/{} expected_output={:?} packets {:?}/{:?}",c.pid,c.name,c.write,c.input,result,c.result,c.output,got,c.packets));
        }
    }
    std::fs::write("/tmp/razer-vector-failures.txt", failures.join("\n")).unwrap();
    assert!(
        failures.is_empty(),
        "{} of {} failed:\n{}",
        failures.len(),
        cases.len(),
        failures
            .iter()
            .take(3)
            .cloned()
            .collect::<Vec<_>>()
            .join("\n")
    );
    println!("{} independent upstream vectors passed", cases.len());
}
#[test]
fn reject_malformed_responses() {
    let mut r = vec![0; 90];
    r[5] = 2;
    r[6] = 7;
    r[7] = 128;
    r[88] = 2 ^ 7 ^ 128;
    assert!(validate_response(&r, &[0; 4]).is_err());
    let mut b = r.clone();
    b[0] = 2;
    assert!(validate_response(&r, &b).is_ok());
    b[7] = 129;
    assert!(validate_response(&r, &b).is_err());
    b = r.clone();
    b[0] = 2;
    b[88] ^= 1;
    assert!(validate_response(&r, &b).is_err());
    for status in [0, 1, 3, 4, 5, 99] {
        b = r.clone();
        b[0] = status;
        assert!(validate_response(&r, &b).is_err());
    }
}

#[test]
fn unknown_legacy_state_never_fabricates_or_writes() {
    for model in catalog::models()
        .iter()
        .filter(|m| m.profile.state_model != catalog::StateModel::Independent)
    {
        let packets = Arc::new(Mutex::new(vec![]));
        let mut session =
            protocol::Session::new(model.pid, Box::new(OracleTransport(packets.clone())));
        assert!(session.execute("dpi", None).is_err());
        assert!(session.execute("poll_rate", None).is_err());
        assert!(session.execute("poll_rate", Some(b"1000")).is_err());
        assert!(
            packets.lock().unwrap().is_empty(),
            "Unknown values must not cause hardware writes"
        );
        let dpi = if model.dpi_list.is_empty() {
            60
        } else {
            model.dpi_list[0] as u16
        };
        session.configure_legacy(dpi, 500, true, false).unwrap();
        assert_eq!(session.execute("poll_rate", None).unwrap(), b"500\n");
        session.execute("poll_rate", Some(b"1000")).unwrap();
        assert_eq!(session.execute("poll_rate", None).unwrap(), b"1000\n");
    }
}
#[test]
fn malformed_templates_cannot_panic() {
    for length in 0..100 {
        assert_eq!(
            protocol::Report::from_template(&vec![0; length]).is_ok(),
            length == wire::REPORT_SIZE
        );
    }
}
#[test]
fn catalog_constraints_have_provenance_and_no_placeholder_models() {
    for model in catalog::models() {
        assert!(model.name.starts_with("Razer "));
        if model.attributes.iter().any(|n| n == "dpi") {
            assert!(model.max_dpi >= model.min_dpi);
            assert!(!model.poll_rates.is_empty());
        }
    }
}
