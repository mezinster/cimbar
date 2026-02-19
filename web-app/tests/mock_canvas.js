'use strict';
/**
 * mock_canvas.js — Minimal Node.js canvas mock for CimBar unit tests.
 *
 * After the drawSymbol fix, the only canvas operations used are:
 *   fillStyle (property)   — set current fill color as '#rrggbb' or 'rgb(r,g,b)'
 *   fillRect(x, y, w, h)   — fill a rectangle of pixels
 *
 * All other canvas methods (arc, stroke, moveTo, …) are no-ops kept for safety.
 */

function parseColor(colorStr) {
  // '#rrggbb'
  const hex = colorStr.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
  if (hex) return [parseInt(hex[1], 16), parseInt(hex[2], 16), parseInt(hex[3], 16)];

  // 'rgb(r,g,b)'
  const rgb = colorStr.match(/^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/);
  if (rgb) return [+rgb[1], +rgb[2], +rgb[3]];

  return [0, 0, 0];
}

class MockCanvas {
  constructor(width, height) {
    this.width  = width;
    this.height = height;
    // RGBA pixel buffer, initialised to opaque black
    this._pixels = new Uint8ClampedArray(width * height * 4);
    for (let i = 3; i < this._pixels.length; i += 4) this._pixels[i] = 255;

    // Canvas 2D context properties
    this.fillStyle   = '#000000';
    this.strokeStyle = '#000000';
    this.lineWidth   = 1;
  }

  getContext(/* type */) { return this; }

  fillRect(x, y, w, h) {
    const [r, g, b] = parseColor(this.fillStyle);
    const x0 = Math.max(0, Math.floor(x));
    const y0 = Math.max(0, Math.floor(y));
    const x1 = Math.min(this.width,  Math.floor(x + w));
    const y1 = Math.min(this.height, Math.floor(y + h));
    for (let py = y0; py < y1; py++) {
      for (let px = x0; px < x1; px++) {
        const i = (py * this.width + px) * 4;
        this._pixels[i]   = r;
        this._pixels[i+1] = g;
        this._pixels[i+2] = b;
        this._pixels[i+3] = 255;
      }
    }
  }

  getImageData(x, y, w, h) {
    // Return a copy to match browser behaviour (real getImageData always copies)
    return { data: this._pixels.slice(), width: this.width, height: this.height };
  }

  // No-op stubs for methods used by old drawSymbol (safe to leave in)
  beginPath() {} closePath() {} stroke() {} fill() {}
  moveTo()    {} lineTo()    {} arc()    {} strokeRect() {}
}

module.exports = { MockCanvas };
