export function verify(input, output, proof = output?.proof) {
  const graph = input.borrowGraph || { nodes: [], edges: [] };
  const schedule = output?.schedule || [];
  if (!proof?.topological) return false;
  if (schedule.length !== (graph.nodes || []).length) return false;
  const pos = new Map(schedule.map((node, index) => [node, index]));
  for (const node of graph.nodes || []) if (!pos.has(node)) return false;
  for (const [from, to] of graph.edges || []) {
    if ((pos.get(from) ?? Infinity) >= (pos.get(to) ?? -1)) return false;
  }
  return true;
}
