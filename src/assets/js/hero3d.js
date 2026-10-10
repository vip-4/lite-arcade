// hero3d.js — 自托管 3D 首屏渲染（零外部依赖，仅在支持 WebGL 且未要求减少动效时加载）
// 资产：src/assets/3d/hero.glb（可用 Blender MCP 生成的真实资产覆盖，无需改代码）
(function () {
  'use strict';
  var container = document.getElementById('hero3d');
  if (!container) return;

  function showPoster() {
    var p = container.querySelector('[data-poster]');
    if (p) p.style.display = 'block';
    var c = container.querySelector('canvas');
    if (c) c.style.display = 'none';
  }

  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function hasWebGL() {
    try {
      var cv = document.createElement('canvas');
      return !!(window.WebGLRenderingContext && (cv.getContext('webgl') || cv.getContext('experimental-webgl')));
    } catch (e) { return false; }
  }

  if (reduce || !hasWebGL()) { showPoster(); return; }

  var THREE;
  function start() {
    Promise.resolve()
      .then(function () { return import('three'); })
      .then(function (mod) { THREE = mod; return fetch(container.getAttribute('data-src') || './assets/3d/hero.glb'); })
      .then(function (r) { return r.arrayBuffer(); })
      .then(function (buf) { init(buf); })
      .catch(function (e) { console.warn('[hero3d] 加载失败，回退：', e); showPoster(); });
  }
  // 推迟到首屏绘制完成后的空闲时段，避免阻塞首屏（three 仅在支持 WebGL 且允许动效时加载）
  if (document.readyState === 'complete') {
    (window.requestIdleCallback || function (f) { setTimeout(f, 200); })(start);
  } else {
    window.addEventListener('load', function () {
      (window.requestIdleCallback || function (f) { setTimeout(f, 200); })(start);
    });
  }

  function parseGLB(arrayBuffer) {
    var dv = new DataView(arrayBuffer);
    if (dv.getUint32(0, true) !== 0x46546C67) throw new Error('not glb');
    var jsonLen = dv.getUint32(12, true);
    var json = JSON.parse(new TextDecoder().decode(new Uint8Array(arrayBuffer, 20, jsonLen)));
    var binStart = 20 + jsonLen;
    // 跳过 bin chunk header(8)
    while (binStart < arrayBuffer.byteLength && dv.getUint32(binStart, true) === 0) binStart++; // 对齐填充
    var binHeader = 8;
    var binOffset = 20 + jsonLen + binHeader;
    var binLen = dv.getUint32(20 + jsonLen, true);
    var bin = new Uint8Array(arrayBuffer, binOffset, binLen);

    function acc(i) {
      var a = json.accessors[i], bv = json.bufferViews[a.bufferView];
      var comp = a.componentType, count = a.count, type = a.type;
      var size = type === 'VEC3' ? 3 : 1;
      var bytes = comp === 5126 ? 4 : (comp === 5123 ? 2 : 1);
      var arr = comp === 5126 ? new Float32Array(bin.buffer, bin.byteOffset + bv.byteOffset, count * size)
                              : new Uint16Array(bin.buffer, bin.byteOffset + bv.byteOffset, count * size);
      return arr;
    }
    var pos = acc(json.meshes[0].primitives[0].attributes.POSITION);
    var nor = acc(json.meshes[0].primitives[0].attributes.NORMAL);
    var ind = acc(json.meshes[0].primitives[0].indices);
    var geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
    geo.setIndex(new THREE.BufferAttribute(ind, 1));
    return geo;
  }

  function proceduralCube() {
    var g = new THREE.BoxGeometry(1.4, 1.4, 1.4, 1, 1, 1);
    g.computeVertexNormals();
    return g;
  }

  function init(arrayBuffer) {
    var geo;
    try { geo = parseGLB(arrayBuffer); }
    catch (e) { console.warn('[hero3d] glb 解析失败，使用程序化立方体', e); geo = proceduralCube(); }

    var scene = new THREE.Scene();
    var cam = new THREE.PerspectiveCamera(45, 1, 0.1, 100);
    cam.position.set(0, 0, 4.2);

    var mat = new THREE.MeshStandardMaterial({
      color: 0x2ee6ff, metalness: 0.55, roughness: 0.3, emissive: 0x0a2a33
    });
    var mesh = new THREE.Mesh(geo, mat);
    scene.add(mesh);

    scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    var key = new THREE.DirectionalLight(0xff6ec7, 1.1); key.position.set(3, 4, 5); scene.add(key);
    var fill = new THREE.DirectionalLight(0x6ee7ff, 0.8); fill.position.set(-4, -2, 2); scene.add(fill);

    var renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setClearColor(0x000000, 0);
    container.appendChild(renderer.domElement);

    var poster = container.querySelector('[data-poster]');
    if (poster) poster.style.display = 'none';

    function resize() {
      var w = container.clientWidth || 320, h = container.clientHeight || 320;
      renderer.setSize(w, h, false);
      cam.aspect = w / h; cam.updateProjectionMatrix();
    }
    resize();
    window.addEventListener('resize', resize);

    var raf;
    (function loop() {
      mesh.rotation.y += 0.008; mesh.rotation.x += 0.003;
      renderer.render(scene, cam);
      raf = requestAnimationFrame(loop);
    })();
  }
})();
