// Copies the split release APKs from the Flutter build into AyomaStore and
// writes public/downloads/release.json, which the store page reads.
//
//   flutter build apk --release --split-per-abi      (in the project root)
//   npm run store:publish -- --notes "Line one|Line two"   (in backend/)
import { copyFileSync, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const backend = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const project = resolve(backend, '..');
const apkDir = join(project, 'build', 'app', 'outputs', 'flutter-apk');
const outDir = join(backend, 'public', 'downloads');
const releasePath = join(outDir, 'release.json');

const builds = [
  { abi: 'arm64', from: 'app-arm64-v8a-release.apk', to: 'Ayoma.apk' },
  { abi: 'armv7', from: 'app-armeabi-v7a-release.apk', to: 'Ayoma-armv7.apk' },
];

const pubspec = readFileSync(join(project, 'pubspec.yaml'), 'utf8');
const version = /^version:\s*([^\s+]+)/m.exec(pubspec)?.[1] ?? '1.0.0';

const notesArg = process.argv.indexOf('--notes');
const previous = existsSync(releasePath) ? JSON.parse(readFileSync(releasePath, 'utf8')) : {};
const notes =
  notesArg > 0
    ? process.argv[notesArg + 1].split('|').map((n) => n.trim()).filter(Boolean)
    : (previous.notes ?? []);

mkdirSync(outDir, { recursive: true });
const files = {};
for (const build of builds) {
  const source = join(apkDir, build.from);
  if (!existsSync(source)) {
    console.error(`Missing ${source}\nRun: flutter build apk --release --split-per-abi`);
    process.exit(1);
  }
  copyFileSync(source, join(outDir, build.to));
  files[build.abi] = { file: `/downloads/${build.to}`, sizeBytes: statSync(source).size };
}

const release = { version, updatedAt: new Date().toISOString(), minAndroid: '7.0', notes, files };
writeFileSync(releasePath, `${JSON.stringify(release, null, 2)}\n`);
console.log(`AyomaStore now serves Ayoma ${version}:`);
for (const [abi, f] of Object.entries(files)) console.log(`  ${abi}: ${f.file} (${(f.sizeBytes / 1048576).toFixed(1)} MB)`);
