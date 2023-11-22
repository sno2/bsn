export function blue(string) {
  return "\x1b[34m" + string + "\x1b[0m";
}

export function gray(string) {
  return "\x1b[90m" + string + "\x1b[0m";
}

export function green(string) {
  return "\x1b[32m" + string + "\x1b[0m";
}

export function underline(string) {
  return "\x1b[4m" + string + "\x1b[0m";
}
