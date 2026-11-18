/** Synthetic metadata workload; its opaque payload is deliberately not GIS-valid. */
export function capacityFixture() {
  const total = 1024 ** 3;
  const remaining = total - 64;
  const size = Math.floor(remaining / 99);
  return Array.from({ length: 100 }, (_, index) => ({
    name: `capacity_${String(Math.floor(index / 4)).padStart(2, "0")}.${["shp", "shx", "dbf", "prj"][index % 4]}`,
    size: index === 0 ? 64 : size + (index <= remaining % 99 ? 1 : 0),
    byte: index % 251,
  }));
}
export function retainedPayloadBound(files: Array<{ size: number }>) {
  return 3 * files.reduce((sum, file) => sum + file.size, 0) + files[0]!.size;
}
export function localProbeDatabase(uri: string, name: string) {
  const url = new URL(uri);
  if (
    !["postgres:", "postgresql:"].includes(url.protocol) ||
    url.hostname !== "127.0.0.1" ||
    url.port !== "55441" ||
    url.pathname !== "/postgres" ||
    !/^firecheck_devprobe_[a-z0-9]+$/.test(name) ||
    url.search
  )
    throw new Error(
      "Probe requires the explicitly designated loopback disposable PostgreSQL server",
    );
  url.pathname = "/" + name;
  return url.toString();
}
