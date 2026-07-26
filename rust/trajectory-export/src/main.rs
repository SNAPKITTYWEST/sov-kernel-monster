//! CLI tool to generate demo trajectory binary data for the WebGL frontend.
//! Usage: cargo run -- [output_path] [trajectories] [steps]

use trajectory_export::{export_trajectory_to_bin, generate_demo_data};

fn main() {
    let args: Vec<String> = std::env::args().collect();

    let output_path = args.get(1).map(|s| s.as_str()).unwrap_or("trajectory.bin");
    let num_trajectories: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(1000);
    let num_steps: usize = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(500);

    eprintln!("Generating {num_trajectories} trajectories × {num_steps} steps...");
    let data = generate_demo_data(num_steps, num_trajectories, 0.01, 0.3);

    export_trajectory_to_bin(&data, output_path)
        .expect("Failed to export trajectory data");

    let file_size = std::fs::metadata(output_path)
        .map(|m| m.len())
        .unwrap_or(0);

    eprintln!("Output: {output_path} ({:.2} MB)", file_size as f64 / 1_048_576.0);
    eprintln!("Serve with: python -m http.server 8080");
    eprintln!("Then open frontend/index.html and call:");
    eprintln!("  window.loadFromBinary('http://localhost:8080/{output_path}', {num_trajectories}, {num_steps})");
}
