export function punchPriorityOptionIndex(value: number): number {
  if ((value & 2) !== 0) {
    return 2;
  }
  if ((value & 4) !== 0) {
    return 3;
  }
  return value === 0 ? 1 : 0;
}

export function punchPriorityOptionValue(index: number): number {
  if (index === 1) {
    return 0;
  }
  if (index === 2) {
    return 2;
  }
  if (index === 3) {
    return 4;
  }
  return 1;
}
