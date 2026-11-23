// Micro-benchmark runner: warms up, then reports the median of several
// timed batches, in microseconds per call.
export function bench(name, fn, { batch = 2000, batches = 15 } = {}) {
  for (let i = 0; i < batch; i++) fn(i)
  const samples = []
  for (let b = 0; b < batches; b++) {
    const start = process.hrtime.bigint()
    for (let i = 0; i < batch; i++) fn(i)
    samples.push(Number(process.hrtime.bigint() - start) / 1000 / batch)
  }
  samples.sort((a, b) => a - b)
  const median = samples[Math.floor(samples.length / 2)]
  console.log(`${name.padEnd(48)} ${median.toFixed(2).padStart(9)} µs/call`)
  return median
}
