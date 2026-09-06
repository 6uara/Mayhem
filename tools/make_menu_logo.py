"""Despega el wordmark de MAYHEM del fondo navy con el que vino.

    python tools/make_menu_logo.py

`assets/Logo_And_Banner/mayhem-logo-dark.png` es la marca tal como se entrego:
blanco sobre un navy plano, opaca de punta a punta - no tiene un solo pixel con
alpha. Sirve para una pagina de store, donde el fondo es de la marca. En el menu
no, porque atras hay una ciudad 3D y una imagen opaca la tapa con un rectangulo.

Lo que hace esto es recuperar la transparencia que el archivo nunca tuvo, y no
recortarla a ojo. El original no se toca: la salida es un archivo nuevo.

Como. Un pixel del borde de una letra no es blanco ni navy, es la mezcla que dejo
el antialias: `P = a*F + (1-a)*B`, con `B` el navy (plano y conocido) y `F` el
color de la tinta. Bajarle el alpha por luminancia -el atajo habitual- daria un
wordmark grisaceo y un acento celeste lavado, porque trata cualquier color que no
sea blanco como si estuviera a medio cubrir. Aca en cambio se saca la paleta del
histograma (son cuatro colores planos: el navy, el blanco del wordmark, el celeste
del acento y el azul medio de la bajada), y para cada pixel se busca cual de esas
tintas lo explica mejor como mezcla contra el navy. Eso da `a` **y** devuelve la
tinta a su color pleno, asi que el borde queda limpio y el celeste sigue siendo
celeste.
"""

import struct
import zlib
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets" / "Logo_And_Banner" / "mayhem-logo-dark.png"
TARGET = ROOT / "assets" / "ui" / "mayhem_logo.png"
## Margen transparente que se le deja al recorte, en pixeles del original.
CROP_PADDING = 8

## Cuantas veces tiene que aparecer un color para contar como tinta y no como
## borde. Las zonas planas son miles de pixeles; un borde antialiaseado, unos
## pocos por tono.
PALETTE_MIN_COUNT = 400
## Y a que distancia del navy tiene que estar para ser tinta y no fondo. El navy
## no es del todo plano -tiene un degrade suave, que en el histograma aparece
## como un segundo color de miles de pixeles-, y sin este piso ese degrade entra
## como tinta y deja un fantasma navy sobre toda la imagen en vez de fondo
## transparente. Las tintas de verdad estan a 200 o mas; el degrade, a 21.
PALETTE_MIN_DISTANCE = 60.0


def read_png(path):
	data = path.read_bytes()
	offset = 8
	pixels = b""
	width = height = 0
	while offset < len(data):
		length = struct.unpack(">I", data[offset:offset + 4])[0]
		kind = data[offset + 4:offset + 8]
		if kind == b"IHDR":
			width, height, depth, colour = struct.unpack(">IIBB", data[offset + 8:offset + 18])
			if depth != 8 or colour != 6:
				raise SystemExit("se esperaba RGBA de 8 bits, vino depth=%d colour=%d" % (depth, colour))
		elif kind == b"IDAT":
			pixels += data[offset + 8:offset + 8 + length]
		offset += 12 + length
	return width, height, _unfilter(zlib.decompress(pixels), width, height)


def _unfilter(raw, width, height):
	stride = width * 4
	out = bytearray()
	previous = bytearray(stride)
	cursor = 0
	for _ in range(height):
		kind = raw[cursor]
		cursor += 1
		line = bytearray(raw[cursor:cursor + stride])
		cursor += stride
		for x in range(stride):
			left = line[x - 4] if x >= 4 else 0
			up = previous[x]
			corner = previous[x - 4] if x >= 4 else 0
			if kind == 1:
				line[x] = (line[x] + left) & 255
			elif kind == 2:
				line[x] = (line[x] + up) & 255
			elif kind == 3:
				line[x] = (line[x] + (left + up) // 2) & 255
			elif kind == 4:
				pa, pb, pc = abs(up - corner), abs(left - corner), abs(left + up - 2 * corner)
				near = left if (pa <= pb and pa <= pc) else (up if pb <= pc else corner)
				line[x] = (line[x] + near) & 255
		out += line
		previous = line
	return bytes(out)


def write_png(path, width, height, pixels):
	raw = bytearray()
	stride = width * 4
	for y in range(height):
		raw.append(0)  # sin filtro: el archivo es chico y asi es reproducible
		raw += pixels[y * stride:(y + 1) * stride]

	def chunk(kind, payload):
		body = kind + payload
		return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_bytes(
		b"\x89PNG\r\n\x1a\n"
		+ chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
		+ chunk(b"IDAT", zlib.compress(bytes(raw), 9))
		+ chunk(b"IEND", b""))


## Recorta al rectangulo que realmente tiene tinta, con `CROP_PADDING` de aire.
def _crop(pixels, width, height):
	left, top, right, bottom = width, height, -1, -1
	for y in range(height):
		row = y * width * 4
		for x in range(width):
			if pixels[row + x * 4 + 3] > 0:
				left = min(left, x)
				right = max(right, x)
				top = min(top, y)
				bottom = max(bottom, y)
	if right < 0:
		raise SystemExit("no quedo un solo pixel con tinta")
	left = max(left - CROP_PADDING, 0)
	top = max(top - CROP_PADDING, 0)
	right = min(right + CROP_PADDING, width - 1)
	bottom = min(bottom + CROP_PADDING, height - 1)
	cropped = bytearray()
	for y in range(top, bottom + 1):
		start = (y * width + left) * 4
		cropped += pixels[start:start + (right - left + 1) * 4]
	return bytes(cropped), right - left + 1, bottom - top + 1


def _distance(a, b):
	return sum((a[c] - b[c]) ** 2 for c in range(3)) ** 0.5


def main():
	width, height, pixels = read_png(SOURCE)
	background = tuple(pixels[0:3])

	counts = Counter()
	for i in range(0, len(pixels), 4):
		counts[pixels[i:i + 3]] += 1
	inks = [tuple(colour) for colour, count in counts.items()
		if count >= PALETTE_MIN_COUNT
		and _distance(tuple(colour), background) >= PALETTE_MIN_DISTANCE]
	if not inks:
		raise SystemExit("no se encontro ninguna tinta: revisa PALETTE_MIN_COUNT")
	print("navy del fondo: %s" % (background,))
	print("tintas: %s" % (inks,))

	out = bytearray(len(pixels))
	for i in range(0, len(pixels), 4):
		pixel = (pixels[i], pixels[i + 1], pixels[i + 2])
		best_ink, best_alpha, best_error = inks[0], 0.0, None
		for ink in inks:
			axis = [ink[c] - background[c] for c in range(3)]
			length = sum(v * v for v in axis)
			if length == 0:
				continue
			# Proyeccion del pixel sobre la recta navy->tinta: cuanto la cubre.
			alpha = sum((pixel[c] - background[c]) * axis[c] for c in range(3)) / length
			alpha = min(max(alpha, 0.0), 1.0)
			error = sum((pixel[c] - (background[c] + alpha * axis[c])) ** 2 for c in range(3))
			if best_error is None or error < best_error:
				best_ink, best_alpha, best_error = ink, alpha, error
		out[i:i + 3] = bytes(best_ink)
		out[i + 3] = int(round(best_alpha * 255))

	# Recortado al wordmark. El original es 2400x840 con la marca chica en el
	# medio y todo lo demas fondo; ese margen, ya transparente, seria espacio
	# muerto que el layout del menu tendria que compensar a mano.
	out, width, height = _crop(bytes(out), width, height)
	write_png(TARGET, width, height, out)
	opaque = sum(1 for i in range(3, len(out), 4) if out[i] > 250)
	print("%s  %dx%d  (%d pixeles de tinta plena)"
		% (TARGET.relative_to(ROOT), width, height, opaque))


if __name__ == "__main__":
	main()
