/**
 * svgo-entry.js — Wrapper d'entrée pour `bun build --compile`
 *
 * Ce fichier est le point d'entrée compilé par Bun pour produire le binaire `svgo` embarqué.
 * Il importe depuis `dist/svgo-node.cjs` (bundle CJS produit par rollup dans le repo svgo)
 * et non depuis `bin/svgo.js` directement, car css-tree charge patch.json dynamiquement
 * d'une façon que le bundler Bun ne résout pas correctement depuis bin/svgo.js.
 *
 * Interface CLI compatible avec ImageOptimizer.swift :
 *   svgo -i input.svg -o output.svg [--multipass]
 *   svgo input.svg [-o output.svg] [--multipass]
 *
 * Commandes de compilation (depuis tools/submodules/svgo/) :
 *   bun install
 *   bun run build          # produit dist/svgo-node.cjs via rollup
 *   MACOSX_DEPLOYMENT_TARGET=14.0 bun build --compile ../../scripts/svgo-entry.js --outfile ../../bin/svgo
 *
 * Validé : svgo 4.0.1, Bun 1.3.11, macOS arm64
 */

import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { optimize } from "../submodules/svgo/dist/svgo-node.cjs";

const args = process.argv.slice(2);

if (args.length === 0) {
  console.error("Usage: svgo -i input.svg -o output.svg [--multipass]");
  process.exit(1);
}

// Parse flags: -i/--input, -o/--output, --multipass
let inputFile = null;
let outputFile = null;
let multipass = false;

for (let i = 0; i < args.length; i++) {
  if ((args[i] === "-i" || args[i] === "--input") && i + 1 < args.length) {
    inputFile = resolve(args[++i]);
  } else if ((args[i] === "-o" || args[i] === "--output") && i + 1 < args.length) {
    outputFile = resolve(args[++i]);
  } else if (args[i] === "--multipass") {
    multipass = true;
  } else if (!args[i].startsWith("-") && !inputFile) {
    inputFile = resolve(args[i]);
  }
}

if (!inputFile) {
  console.error("Erreur : fichier d'entrée requis (-i input.svg)");
  process.exit(1);
}

try {
  const input = readFileSync(inputFile, "utf8");
  const result = optimize(input, { path: inputFile, multipass });

  if (outputFile) {
    writeFileSync(outputFile, result.data);
  } else {
    writeFileSync(inputFile, result.data);
  }
} catch (err) {
  console.error(`Erreur : ${err.message}`);
  process.exit(1);
}
