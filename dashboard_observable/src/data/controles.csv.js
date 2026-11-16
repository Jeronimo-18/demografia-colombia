import {readFile} from "node:fs/promises";
import path from "node:path";

const filePath = path.resolve(process.cwd(), "..", "resultados", "controles.csv");

try {
  process.stdout.write(await readFile(filePath, "utf8"));
} catch (error) {
  process.stderr.write(`No se pudo leer resultados/controles.csv (${filePath}): ${error.message}\n`);
  process.exitCode = 1;
}
