export function verify(input, output, proof = output?.proof) {
  const entry = input.entry || {};
  const debit = Number(entry.debit || 0);
  const credit = Number(entry.credit || 0);
  return Boolean(output?.valid === (debit === credit) && proof?.balanced === (debit === credit));
}
