//! SEB (Sovereign Event Bus) Erlang/OTP node launcher

pub fn spawn_seb_node() -> bool {
    let result = std::process::Command::new("erl")
        .arg("-noshell")
        .arg("-eval")
        .arg("seb_supervisor:boot(), timer:sleep(infinity).")
        .spawn();
    
    result.is_ok()
}
