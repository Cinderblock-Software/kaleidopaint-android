# Drawings in older file formats

Hand-built inputs for the decoder tests, one per file format version from 1.0
to 1.9, following the rules in upstream's `decodeFileFormat()`: colours as a
base colour and a brightness (1.4 and earlier), the wallpaper group as a
number (1.5 and earlier), half-thicknesses and the old property names (1.6 and
earlier), and so on. `whitespace.kaleidopaint` is a current-format drawing
with CR LF line ends, no-break spaces and no final newline.

They are not drawings made by any version of KaleidoPaint. Upstream's own
decoder reads them (`tools/reference/build.sh`) and what it makes of them is
the reference the Kotlin decoder is compared with.
