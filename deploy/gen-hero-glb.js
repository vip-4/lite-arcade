// gen-hero-glb.js — 生成占位 3D 资产（霓虹立方体），用于验证 3D hero 管线。
// 真实资产请在本机用 Blender MCP 生成后覆盖 src/assets/3d/hero.glb，无需改动任何代码。
const fs = require('fs');
const path = require('path');

// 立方体：24 顶点（每面 4 个），含法线；36 索引
const faces = [
  { n: [0, 0, 1], v: [[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]] },
  { n: [0, 0,-1], v: [[1,-1,-1],[-1,-1,-1],[-1,1,-1],[1,1,-1]] },
  { n: [1, 0, 0], v: [[1,-1,1],[1,-1,-1],[1,1,-1],[1,1,1]] },
  { n: [-1,0, 0], v: [[-1,-1,-1],[-1,-1,1],[-1,1,1],[-1,1,-1]] },
  { n: [0, 1, 0], v: [[-1,1,1],[1,1,1],[1,1,-1],[-1,1,-1]] },
  { n: [0,-1, 0], v: [[-1,-1,-1],[1,-1,-1],[1,-1,1],[-1,-1,1]] },
];
const pos = [], nor = [], idx = [];
faces.forEach((f, fi) => {
  f.v.forEach(p => { pos.push(...p); nor.push(...f.n); });
  const base = fi * 4;
  idx.push(base, base+1, base+2, base, base+2, base+3);
});

const posBuf = Buffer.alloc(pos.length * 4);
const norBuf = Buffer.alloc(nor.length * 4);
const idxBuf = Buffer.alloc(idx.length * 2);
pos.forEach((v,i) => posBuf.writeFloatLE(v, i*4));
nor.forEach((v,i) => norBuf.writeFloatLE(v, i*4));
idx.forEach((v,i) => idxBuf.writeUInt16LE(v, i*2));

const bin = Buffer.concat([posBuf, norBuf, idxBuf]);
const posLen = posBuf.length, norLen = norBuf.length, idxLen = idxBuf.length;
const json = {
  asset: { version: '2.0', generator: 'lite-arcade-placeholder' },
  scene: 0,
  scenes: [{ nodes: [0] }],
  nodes: [{ mesh: 0, name: 'hero' }],
  meshes: [{ primitives: [{ attributes: { POSITION: 0, NORMAL: 1 }, indices: 2, material: 0 }] }],
  materials: [{ name: 'neon', pbrMetallicRoughness: { baseColorFactor: [0.18, 0.85, 1.0, 1.0], metallicFactor: 0.55, roughnessFactor: 0.3 } }],
  buffers: [{ byteLength: bin.length }],
  bufferViews: [
    { buffer: 0, byteOffset: 0, byteLength: posLen, target: 34962 },
    { buffer: 0, byteOffset: posLen, byteLength: norLen, target: 34962 },
    { buffer: 0, byteOffset: posLen + norLen, byteLength: idxLen, target: 34963 },
  ],
  accessors: [
    { bufferView: 0, componentType: 5126, count: pos.length/3, type: 'VEC3', min: [-1,-1,-1], max: [1,1,1] },
    { bufferView: 1, componentType: 5126, count: nor.length/3, type: 'VEC3' },
    { bufferView: 2, componentType: 5123, count: idx.length, type: 'SCALAR' },
  ],
};

function pad(buf, size) {
  const rem = buf.length % size;
  return rem ? Buffer.concat([buf, Buffer.alloc(size - rem)]) : buf;
}
const jsonBuf = pad(Buffer.from(JSON.stringify(json), 'utf8'), 4);
const binBuf = pad(bin, 4);
const total = 12 + 8 + jsonBuf.length + 8 + binBuf.length;
const header = Buffer.alloc(12);
header.writeUInt32LE(0x46546C67, 0); header.writeUInt32LE(2, 4); header.writeUInt32LE(total, 8);
const jsonChunk = Buffer.alloc(8); jsonChunk.writeUInt32LE(jsonBuf.length, 0); jsonChunk.writeUInt32LE(0x4E4F534A, 4);
const binChunk = Buffer.alloc(8); binChunk.writeUInt32LE(binBuf.length, 0); binChunk.writeUInt32LE(0x004E4942, 4);
const glb = Buffer.concat([header, jsonChunk, jsonBuf, binChunk, binBuf]);

const outDir = path.resolve(__dirname, '..', 'src', 'assets', '3d');
fs.mkdirSync(outDir, { recursive: true });
const out = path.join(outDir, 'hero.glb');
fs.writeFileSync(out, glb);
console.log(`[gen-hero-glb] 已生成占位资产: ${out} (${(glb.length/1024).toFixed(1)} KB)`);
