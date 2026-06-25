class_name Icon
extends RefCounted
# Tiny helper: recolor a solid-shape icon (e.g. the arrow art) to a flat color while keeping
# its alpha silhouette. The arrow ships green; we discard the source RGB and paint `color`
# wherever the source is opaque, so it matches the UI text. A plain modulate can't do this —
# multiplying a color into green's zero R/B channels can never brighten them.

static func recolored(src: Texture2D, color: Color, size: int = 64) -> ImageTexture:
	var img := src.get_image()
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(color.r, color.g, color.b, a))
	return ImageTexture.create_from_image(img)
