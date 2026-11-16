import {readFile} from "node:fs/promises";
import path from "node:path";

const filePath = path.resolve(process.cwd(), "..", "resultados", "escenarios_poblacion.csv");

try {
  process.stdout.write(await readFile(filePath, "utf8"));
} catch (error) {
  process.stderr.write(`No se pudo leer resultados/escenarios_poblacion.csv (${filePath}): ${error.message}\n`);
  process.exitCode = 1;
}
