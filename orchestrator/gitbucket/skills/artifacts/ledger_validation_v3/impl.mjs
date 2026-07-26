export function run(input) {
  const entry = input.entry || {};
  const debit = Number(entry.debit || 0);
  const credit = Number(entry.credit || 0);
  return {
    valid: debit === credit,
    proof: {
      balanced: debit === credit,
      debit,
      credit
    }
  };
}
