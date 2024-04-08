//! * fontAtlas.h
//!
//! Provides functions for generating font atlases of several kinds on macOS:
//! - Standard
//! - SDF
//!
//! This library uses Apple/macOS frameworks, such as CoreText for text layout.
//!
//! ** Compiling
//!
//! To compile as an executable test:
//!
//! ```
//! > clang -DCOMPILE_AS_TEST -fmodules -fobjc-arc -framework AppKit -framework CoreText fontAtlas.m -o typing
//! ```
//!
//! ** Usage
//!
//! - All C-style strings must be UTF-8 encoded and null-terminated.
//!
//! ** Debugging
//!
//! To use Apple's Instruments, save the following, e.g. to `debug.plist`:
//!
//! ```
//! <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>
//! ```
//!
//! Compile with debug info (`-g` in clang) and apply the signature with
//!
//! ```
//! > codesign -s - -v -f --entitlements ./debug.plist ./typing
//! ```
//!
//! ** Credits
//!
//! - Metal by Example: Rendering Text in Metal with Signed-Distance Fields
//!   [link](https://metalbyexample.com/rendering-text-in-metal-with-signed-distance-fields/)

struct GlyphDescriptors {
  CGPoint *topLeftTexCoords;
  CGPoint *bottomRightTexCoords;
};

struct FontAtlas {
  uint8_t *imageData;
  size_t width;
  size_t height;
  struct GlyphDescriptors glyphDescriptors;
};

void fontAtlasFree(struct FontAtlas fontAtlas);

/// Creates a font atlas for the specified font. Returns NULL on any error.
///
/// The resulting atlas will have dimensions `atlasWidth` by `atlasHeight`. This function will try
/// to pick the largest font size such that all glyphs will fit in the specified atlas size.
struct FontAtlas createAtlasForFont(const char *fontName, size_t atlasWidth, size_t atlasHeight);

/// Creates an SDF corresponding the a grayscale image.
///
/// Considers `imageData` as a `width` by `height` array (i.e. it has `width*height` elements).
float* createSdfForGrayscaleImage(const uint8_t *imageData, size_t width, size_t height);

/// Write a visualization of the SDF to a TIFF file.
///
/// Considers `sdfData` as a `width` by `height` array (i.e. it has `width*height` elements).
/// Writes the result to `path`, which is allowed to be a relative path.
void writeSdfToTiffFile(const float* sdfData, float width, float height, const char *path);
