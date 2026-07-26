//! Runtime Performance Benchmarks

use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId, Throughput};
use shadow_rpg_q::{Job, JobQueue, Journal, Receipt, Executor};
use std::time::Duration;

fn benchmark_job_creation(c: &mut Criterion) {
    let mut group = c.benchmark_group("job_creation");
    
    let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
    
    group.bench_function("create_job", |b| {
        b.iter(|| {
            Job::new(
                black_box("test-job"),
                black_box(source),
                black_box("heron-r3"),
                black_box(5),
            )
        });
    });
    
    group.finish();
}

fn benchmark_queue_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("queue_operations");
    
    let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
    
    // Single job operations
    group.bench_function("enqueue_single", |b| {
        b.iter(|| {
            let mut queue = JobQueue::new();
            let job = Job::new("test-job", source, "heron-r3", 5);
            queue.enqueue(black_box(job)).unwrap()
        });
    });
    
    group.bench_function("dequeue_single", |b| {
        let mut queue = JobQueue::new();
        let job = Job::new("test-job", source, "heron-r3", 5);
        queue.enqueue(job).unwrap();
        
        b.iter(|| {
            let mut q = queue.clone();
            q.dequeue().unwrap()
        });
    });
    
    // Batch operations
    for batch_size in [10, 50, 100, 500].iter() {
        group.throughput(Throughput::Elements(*batch_size as u64));
        
        group.bench_with_input(
            BenchmarkId::new("enqueue_batch", batch_size),
            batch_size,
            |b, &size| {
                b.iter(|| {
                    let mut queue = JobQueue::new();
                    for i in 0..size {
                        let job = Job::new(
                            &format!("job-{}", i),
                            source,
                            "heron-r3",
                            5,
                        );
                        queue.enqueue(job).unwrap();
                    }
                });
            },
        );
        
        group.bench_with_input(
            BenchmarkId::new("dequeue_batch", batch_size),
            batch_size,
            |b, &size| {
                b.iter(|| {
                    let mut queue = JobQueue::new();
                    for i in 0..size {
                        let job = Job::new(
                            &format!("job-{}", i),
                            source,
                            "heron-r3",
                            5,
                        );
                        queue.enqueue(job).unwrap();
                    }
                    
                    for _ in 0..size {
                        queue.dequeue().unwrap();
                    }
                });
            },
        );
    }
    
    group.finish();
}

fn benchmark_priority_queue(c: &mut Criterion) {
    let mut group = c.benchmark_group("priority_queue");
    
    let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
    
    for num_jobs in [10, 50, 100].iter() {
        group.bench_with_input(
            BenchmarkId::new("priority_ordering", num_jobs),
            num_jobs,
            |b, &n| {
                b.iter(|| {
                    let mut queue = JobQueue::new();
                    
                    // Enqueue jobs with varying priorities
                    for i in 0..n {
                        let priority = (i % 10) as u8;
                        let job = Job::new(
                            &format!("job-{}", i),
                            source,
                            "heron-r3",
                            priority,
                        );
                        queue.enqueue(job).unwrap();
                    }
                    
                    // Dequeue all (should be priority-ordered)
                    for _ in 0..n {
                        queue.dequeue().unwrap();
                    }
                });
            },
        );
    }
    
    group.finish();
}

fn benchmark_journal_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("journal_operations");
    
    let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
    let job = Job::new("test-job", source, "heron-r3", 5);
    
    group.bench_function("write_entry", |b| {
        b.iter(|| {
            let mut journal = Journal::new();
            journal.write_entry(
                black_box("RECEIVED"),
                black_box(&job),
                black_box("Job received"),
            ).unwrap()
        });
    });
    
    group.bench_function("read_entries", |b| {
        let mut journal = Journal::new();
        for i in 0..100 {
            journal.write_entry(
                "RECEIVED",
                &job,
                &format!("Entry {}", i),
            ).unwrap();
        }
        
        b.iter(|| {
            journal.read_entries(black_box("test-job")).unwrap()
        });
    });
    
    // Batch journal writes
    for batch_size in [10, 50, 100, 500].iter() {
        group.throughput(Throughput::Elements(*batch_size as u64));
        
        group.bench_with_input(
            BenchmarkId::new("write_batch", batch_size),
            batch_size,
            |b, &size| {
                b.iter(|| {
                    let mut journal = Journal::new();
                    for i in 0..size {
                        journal.write_entry(
                            "RECEIVED",
                            &job,
                            &format!("Entry {}", i),
                        ).unwrap();
                    }
                });
            },
        );
    }
    
    group.finish();
}

fn benchmark_receipt_generation(c: &mut Criterion) {
    let mut group = c.benchmark_group("receipt_generation");
    
    let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
    let job = Job::new("test-job", source, "heron-r3", 5);
    
    group.bench_function("create_receipt", |b| {
        b.iter(|| {
            Receipt::new(
                black_box(&job),
                black_box("COMPLETED"),
                black_box("Success"),
            )
        });
    });
    
    group.bench_function("seal_receipt", |b| {
        let receipt = Receipt::new(&job, "COMPLETED", "Success");
        
        b.iter(|| {
            let mut r = receipt.clone();
            r.seal().unwrap()
        });
    });
    
    group.bench_function("verify_receipt", |b| {
        let mut receipt = Receipt::new(&job, "COMPLETED", "Success");
        receipt.seal().unwrap();
        
        b.iter(|| {
            black_box(&receipt).verify().unwrap()
        });
    });
    
    group.finish();
}

fn benchmark_executor(c: &mut Criterion) {
    let mut group = c.benchmark_group("executor");
    
    let test_cases = vec![
        ("bell_state", "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];"),
        ("ghz_3", "OPENQASM 2.0; qreg q[3]; h q[0]; cx q[0],q[1]; cx q[1],q[2];"),
        ("ghz_5", "OPENQASM 2.0; qreg q[5]; h q[0]; cx q[0],q[1]; cx q[1],q[2]; cx q[2],q[3]; cx q[3],q[4];"),
    ];
    
    for (name, source) in test_cases {
        group.bench_with_input(
            BenchmarkId::new("execute_job", name),
            &source,
            |b, s| {
                b.iter(|| {
                    let mut executor = Executor::new();
                    let job = Job::new("test-job", black_box(s), "simulator", 5);
                    executor.execute(job).unwrap()
                });
            },
        );
    }
    
    group.finish();
}

fn benchmark_full_workflow(c: &mut Criterion) {
    let mut group = c.benchmark_group("full_workflow");
    
    let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
    
    group.bench_function("submit_execute_retrieve", |b| {
        b.iter(|| {
            // Create job
            let job = Job::new("test-job", black_box(source), "simulator", 5);
            
            // Enqueue
            let mut queue = JobQueue::new();
            queue.enqueue(job.clone()).unwrap();
            
            // Journal
            let mut journal = Journal::new();
            journal.write_entry("RECEIVED", &job, "Job received").unwrap();
            
            // Execute
            let mut executor = Executor::new();
            let result = executor.execute(job.clone()).unwrap();
            
            // Create receipt
            let mut receipt = Receipt::new(&job, "COMPLETED", "Success");
            receipt.seal().unwrap();
            
            // Verify
            receipt.verify().unwrap();
            
            result
        });
    });
    
    group.finish();
}

fn benchmark_concurrent_jobs(c: &mut Criterion) {
    let mut group = c.benchmark_group("concurrent_jobs");
    
    let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
    
    for num_jobs in [5, 10, 20].iter() {
        group.throughput(Throughput::Elements(*num_jobs as u64));
        
        group.bench_with_input(
            BenchmarkId::new("parallel_execution", num_jobs),
            num_jobs,
            |b, &n| {
                b.iter(|| {
                    let mut executor = Executor::new();
                    let mut results = Vec::new();
                    
                    for i in 0..n {
                        let job = Job::new(
                            &format!("job-{}", i),
                            source,
                            "simulator",
                            5,
                        );
                        results.push(executor.execute(job).unwrap());
                    }
                    
                    results
                });
            },
        );
    }
    
    group.finish();
}

fn benchmark_recovery(c: &mut Criterion) {
    let mut group = c.benchmark_group("recovery");
    
    let source = "OPENQASM 2.0; qreg q[2]; h q[0]; cx q[0],q[1];";
    
    group.bench_function("journal_replay", |b| {
        // Create journal with 100 entries
        let mut journal = Journal::new();
        let job = Job::new("test-job", source, "simulator", 5);
        
        for i in 0..100 {
            journal.write_entry(
                "RECEIVED",
                &job,
                &format!("Entry {}", i),
            ).unwrap();
        }
        
        b.iter(|| {
            // Simulate recovery by reading all entries
            let entries = journal.read_entries(black_box("test-job")).unwrap();
            black_box(entries)
        });
    });
    
    group.finish();
}

criterion_group!(
    benches,
    benchmark_job_creation,
    benchmark_queue_operations,
    benchmark_priority_queue,
    benchmark_journal_operations,
    benchmark_receipt_generation,
    benchmark_executor,
    benchmark_full_workflow,
    benchmark_concurrent_jobs,
    benchmark_recovery
);
criterion_main!(benches);

// Made with Bob
