//! Build script to generate C header file

use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let output_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    
    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_language(cbindgen::Language::C)
        .with_include_guard("QATAAUM_IBMI_FFI_H")
        .with_documentation(true)
        .with_pragma_once(true)
        .generate()
        .expect("Unable to generate C bindings")
        .write_to_file(output_dir.join("qataaum.h"));
    
    println!("cargo:rerun-if-changed=src/lib.rs");
}

// Made with Bob
