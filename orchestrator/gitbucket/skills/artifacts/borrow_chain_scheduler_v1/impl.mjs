export function run(input) {
  const graph = input.borrowGraph || { nodes: [], edges: [] };
  const nodes = [...(graph.nodes || [])];
  const edges = graph.edges || [];
  const incoming = new Map(nodes.map((node) => [node, 0]));
  const outgoing = new Map(nodes.map((node) => [node, []]));
  for (const [from, to] of edges) {
    incoming.set(to, (incoming.get(to) || 0) + 1);
    outgoing.get(from)?.push(to);
  }
  const queue = nodes.filter((node) => incoming.get(node) === 0).sort();
  const schedule = [];
  while (queue.length) {
    const node = queue.shift();
    schedule.push(node);
    for (const to of outgoing.get(node) || []) {
      incoming.set(to, incoming.get(to) - 1);
      if (incoming.get(to) === 0) queue.push(to);
    }
    queue.sort();
  }
  return {
    schedule,
    proof: {
      topological: schedule.length === nodes.length,
      nodeCount: nodes.length,
      edgeCount: edges.length
    }
  };
}
