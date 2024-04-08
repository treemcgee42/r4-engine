#define R4_GENERATE_DEBUG_ATLAS_IMAGE 1

@import AppKit;
@import CoreText;
#include "fontAtlas.h"

static CGSize averageGlyphSizeForFont(NSFont *font) {
  NSString *testString = @"{ǺOJMQYZa@jmqyw";
  CGSize testStringSize = [testString sizeWithAttributes:@{ NSFontAttributeName : font }];
  CGFloat averageGlyphWidth = ceilf(testStringSize.width / testString.length);
  CGFloat maxGlyphHeight = ceilf(testStringSize.height);

  return CGSizeMake(averageGlyphWidth, maxGlyphHeight);
}

static CGFloat glyphMarginForFont(NSFont *font) {
  CGFloat estimate = [@"!" sizeWithAttributes:@{ NSFontAttributeName : font }].width;
  return ceilf(estimate);
}

static BOOL fontPointSizeFitsInAtlas(NSFont *font, CGFloat pointSize, CGRect atlasRect) {
  const float textureArea = atlasRect.size.width * atlasRect.size.height;

  float glyphArea;
  NSFont *testFont = [NSFont fontWithName:font.fontName size:pointSize];
  CTFontRef testCTFont = CTFontCreateWithName((__bridge CFStringRef)font.fontName,
                                              pointSize, NULL);
  CFIndex fontGlyphCount = CTFontGetGlyphCount(testCTFont);
  CGFloat glyphMargin = glyphMarginForFont(testFont);
  CGSize averageGlyphSize = averageGlyphSizeForFont(testFont);
  glyphArea = (averageGlyphSize.width + glyphMargin) * (averageGlyphSize.height + glyphMargin)
              * fontGlyphCount;

  CFRelease(testCTFont);
  return (glyphArea < textureArea);
}

static CGFloat largestValidFontPointSizeForAtlas(NSFont *font, CGRect atlasRect) {
  CGFloat pointSize = font.pointSize;

  // The double while loops allows us to start testing from the initial font point size.
  
  while (fontPointSizeFitsInAtlas(font, pointSize, atlasRect)) {
    pointSize += 1;
  }

  while (!fontPointSizeFitsInAtlas(font, pointSize, atlasRect)) {
    pointSize -= 1;
  }

  return pointSize;
}

struct FontAtlas createAtlasForFont(const char *fontName, size_t width, size_t height) {
  NSFont *font = [NSFont fontWithName:[NSString stringWithUTF8String:fontName] size:12];
  if (font == NULL) {
    fprintf(stderr, "%s invalid font\n", __func__);
    return (struct FontAtlas){
      .imageData = NULL,
    };
  }
  
  // === Set up the bitmap for the atlas.
  // - 1 byte per pixel is sufficient.
  // - We wish to disable antialiasing so that pixels are fully-on or fully-off (useful for SDF
  //   generation).
  // - Make the coordinate space have top-left as (0,0) and bottom-right as (max,max).
  // - Fill the bitmap with 0s.
  
  uint8_t *imageData = malloc(width * height);
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
  CGBitmapInfo bitmapInfo = (kCGBitmapAlphaInfoMask & kCGImageAlphaNone);
  CGContextRef context = CGBitmapContextCreate(imageData,
                                               width,
                                               height,
                                               8,
                                               width,
                                               colorSpace,
                                               bitmapInfo);
  
  CGContextSetAllowsAntialiasing(context, false);

  CGContextTranslateCTM(context, 0, height);
  CGContextScaleCTM(context, 1, -1);

  CGContextSetRGBFillColor(context, 0, 0, 0, 1);
  CGContextFillRect(context, CGRectMake(0, 0, width, height));

  // === Determine largest font size that will fit in atlas.

  CGFloat fontPointSize = largestValidFontPointSizeForAtlas(font, CGRectMake(0, 0, width, height));
  
  // ===

  NSFont *nsFont = [NSFont fontWithName:font.fontName size:fontPointSize];
  CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef)font.fontName,
                                          fontPointSize,
                                          NULL);

  CFIndex fontGlyphCount = CTFontGetGlyphCount(ctFont);
  CGFloat glyphMargin = glyphMarginForFont(nsFont);

  CGContextSetRGBFillColor(context, 1, 1, 1, 1);

  struct GlyphDescriptors glyphDescriptors;
  glyphDescriptors.topLeftTexCoords = malloc(fontGlyphCount * sizeof(CGPoint));
  glyphDescriptors.bottomRightTexCoords = malloc(fontGlyphCount * sizeof(CGPoint));

  CGFloat fontAscent = CTFontGetAscent(ctFont);
  CGFloat fontDescent = CTFontGetDescent(ctFont);

  CGPoint origin = CGPointMake(0, fontAscent);
  CGFloat maxYCoordForLine = -1;
  for (CGGlyph glyph = 0; glyph < fontGlyphCount; ++glyph) {
    CGRect boundingRect;
    CTFontGetBoundingRectsForGlyphs(ctFont, kCTFontOrientationHorizontal, &glyph,
                                    &boundingRect, 1);

    if (origin.x + CGRectGetMaxX(boundingRect) + glyphMargin > width ) {
      origin.x = 0;
      origin.y = maxYCoordForLine + glyphMargin + fontDescent;
      maxYCoordForLine = -1;
    }
    if (origin.y + CGRectGetMaxY(boundingRect) > maxYCoordForLine) {
      maxYCoordForLine = origin.y + CGRectGetMaxY(boundingRect);
    }
    
    CGFloat glyphOriginX = origin.x - boundingRect.origin.x + (glyphMargin * 0.5);
    CGFloat glyphOriginY = origin.y + (glyphMargin * 0.5);
    
    CGAffineTransform glyphTransform = CGAffineTransformMake(1, 0, 0, -1,
                                                             glyphOriginX, glyphOriginY);
    CGPathRef path = CTFontCreatePathForGlyph(ctFont, glyph, &glyphTransform);
    CGContextAddPath(context, path);
    CGContextFillPath(context);

    // ===
    
    CGRect glyphPathBoundingRect = CGPathGetPathBoundingBox(path);
    if (CGRectEqualToRect(glyphPathBoundingRect, CGRectNull)) {
      glyphPathBoundingRect = CGRectZero;
    }

    CGFloat texCoordLeft = glyphPathBoundingRect.origin.x / width;
    CGFloat texCoordRight = (glyphPathBoundingRect.origin.x + glyphPathBoundingRect.size.width) / width;
    CGFloat texCoordTop = (glyphPathBoundingRect.origin.y) / height;
    CGFloat texCoordBottom = (glyphPathBoundingRect.origin.y + glyphPathBoundingRect.size.height) / height;

    glyphDescriptors.topLeftTexCoords[glyph] = CGPointMake(texCoordLeft, texCoordTop);
    glyphDescriptors.bottomRightTexCoords[glyph] = CGPointMake(texCoordRight, texCoordBottom);
    
    CGPathRelease(path);
    origin.x += CGRectGetWidth(boundingRect) + glyphMargin;
  }

  CFRelease(ctFont);
  CGContextRelease(context);
  CGColorSpaceRelease(colorSpace);

  return (struct FontAtlas){
    .imageData = imageData,
      .width = width,
      .height = height,
      .glyphDescriptors = glyphDescriptors,
  };
}

void writeFontAtlasToTiffFile(const uint8_t *fontAtlas, float width, float height,
                              const char *path) {
  // TODO: this probably isn't necessary. I just did it because the context expects a non-const
  // pointer, and I'm too lazy to look and see if anyting I do with the context could change the
  // data.
  uint8_t *imageData = malloc(width*height*sizeof(uint8_t));
  if (imageData == NULL) {
    fprintf(stderr, "%s failed to allocate imageData\n", __func__);
    return;
  }
  memcpy(imageData, fontAtlas, width*height);
  
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
  CGBitmapInfo bitmapInfo = (kCGBitmapAlphaInfoMask & kCGImageAlphaNone);
  CGContextRef context = CGBitmapContextCreate(imageData,
                                               width,
                                               height,
                                               8,
                                               width,
                                               colorSpace,
                                               bitmapInfo);
  CGContextTranslateCTM(context, 0, height);
  CGContextScaleCTM(context, 1, -1);

  CGImageRef imageRef = CGBitmapContextCreateImage(context);
  NSImage *image = [[NSImage alloc] initWithCGImage:imageRef size:NSZeroSize];

  NSData *tiffData = [image TIFFRepresentation];
  NSString *expandedPath = [[NSString stringWithUTF8String:path] stringByExpandingTildeInPath];
  [tiffData writeToFile:expandedPath atomically:YES];

  CGImageRelease(imageRef);
  CGContextRelease(context);
  CGColorSpaceRelease(colorSpace);
  free(imageData);
}

float* createSdfForGrayscaleImage(const uint8_t *imageData, size_t atlasWidth, size_t atlasHeight) {
  if (imageData == NULL || atlasWidth == 0 || atlasHeight == 0) {
    return NULL;
  }

  typedef struct { unsigned short x, y; } intpoint_t;

  // distance to nearest boundary point map
  float *distanceMap = malloc(atlasWidth * atlasHeight * sizeof(float));
  // nearest boundary point map
  intpoint_t *boundaryPointMap = malloc(atlasWidth * atlasHeight * sizeof(intpoint_t));

  // Some helpers for manipulating the above arrays
#define image(_x, _y) (imageData[(_y) * atlasWidth + (_x)] > 0x7f)
#define distance(_x, _y) distanceMap[(_y) * atlasWidth + (_x)]
#define nearestpt(_x, _y) boundaryPointMap[(_y) * atlasWidth + (_x)]

  const float maxDist = hypot(atlasWidth, atlasHeight);
  const float distUnit = 1;
  const float distDiag = sqrt(2);

  // Initialization phase: set all distances to "infinity"; zero out nearest boundary point map
  for (size_t y = 0; y < atlasHeight; ++y)
    {
      for (size_t x = 0; x < atlasWidth; ++x)
        {
          distance(x, y) = maxDist;
          nearestpt(x, y) = (intpoint_t){ 0, 0 };
        }
    }

  // Immediate interior/exterior phase: mark all points along the boundary as such
  for (size_t y = 1; y < atlasHeight - 1; ++y)
    {
      for (size_t x = 1; x < atlasWidth - 1; ++x)
        {
          bool inside = image(x, y);
          if (image(x - 1, y) != inside ||
              image(x + 1, y) != inside ||
              image(x, y - 1) != inside ||
              image(x, y + 1) != inside)
            {
              distance(x, y) = 0;
              nearestpt(x, y) = (intpoint_t){ x, y };
            }
        }
    }

  // Forward dead-reckoning pass
  for (size_t y = 1; y < atlasHeight - 2; ++y)
    {
      for (size_t x = 1; x < atlasWidth - 2; ++x)
        {
          if (distanceMap[(y - 1) * atlasWidth + (x - 1)] + distDiag < distance(x, y))
            {
              nearestpt(x, y) = nearestpt(x - 1, y - 1);
              distance(x, y) = hypot(x - nearestpt(x, y).x, y - nearestpt(x, y).y);
            }
          if (distance(x, y - 1) + distUnit < distance(x, y))
            {
              nearestpt(x, y) = nearestpt(x, y - 1);
              distance(x, y) = hypot(x - nearestpt(x, y).x, y - nearestpt(x, y).y);
            }
          if (distance(x + 1, y - 1) + distDiag < distance(x, y))
            {
              nearestpt(x, y) = nearestpt(x + 1, y - 1);
              distance(x, y) = hypot(x - nearestpt(x, y).x, y - nearestpt(x, y).y);
            }
          if (distance(x - 1, y) + distUnit < distance(x, y))
            {
              nearestpt(x, y) = nearestpt(x - 1, y);
              distance(x, y) = hypot(x - nearestpt(x, y).x, y - nearestpt(x, y).y);
            }
        }
    }

  // Backward dead-reckoning pass
  for (size_t y = atlasHeight - 2; y >= 1; --y)
    {
      for (size_t x = atlasWidth - 2; x >= 1; --x)
        {
          if (distance(x + 1, y) + distUnit < distance(x, y))
            {
              nearestpt(x, y) = nearestpt(x + 1, y);
              distance(x, y) = hypot(x - nearestpt(x, y).x, y - nearestpt(x, y).y);
            }
          if (distance(x - 1, y + 1) + distDiag < distance(x, y))
            {
              nearestpt(x, y) = nearestpt(x - 1, y + 1);
              distance(x, y) = hypot(x - nearestpt(x, y).x, y - nearestpt(x, y).y);
            }
          if (distance(x, y + 1) + distUnit < distance(x, y))
            {
              nearestpt(x, y) = nearestpt(x, y + 1);
              distance(x, y) = hypot(x - nearestpt(x, y).x, y - nearestpt(x, y).y);
            }
          if (distance(x + 1, y + 1) + distDiag < distance(x, y))
            {
              nearestpt(x, y) = nearestpt(x + 1, y + 1);
              distance(x, y) = hypot(x - nearestpt(x, y).x, y - nearestpt(x, y).y);
            }
        }
    }

  // Interior distance negation pass; distances outside the figure are considered negative
  for (size_t y = 0; y < atlasHeight; ++y)
    {
      for (size_t x = 0; x < atlasWidth; ++x)
        {
          if (!image(x, y))
            distance(x, y) = -distance(x, y);
        }
    }

  free(boundaryPointMap);

  return distanceMap;

#undef image
#undef distance
#undef nearestpt
}

void writeSdfToTiffFile(const float *sdfData, float width, float height, const char *path) {
  // TODO: I found it best to just pick some number that results in a reasonable image.  Ideally
  // this is calculated based on the data. It didn't work to take the absolute maximum of the data
  // since there are some high values in places in the atlas that aren't near any glyphs, resulting
  // in it dominating the rest of the distances.
  const float maxAbsDistance = 10;

  uint8_t *imageData = malloc(width * height);

  for (size_t i=0; i<width*height; ++i) {
    const float distance = sdfData[i];
    const float normalizedDistance = 0.5 * (distance / maxAbsDistance) + 0.5;
    
    imageData[i] = (uint8_t)(normalizedDistance * 255);
  }

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
  CGContextRef context = CGBitmapContextCreate(imageData, width, height, 8, width,
                                               colorSpace, kCGImageAlphaNone);

  CGImageRef imageRef = CGBitmapContextCreateImage(context);
  NSImage *sdfImage = [[NSImage alloc] initWithCGImage:imageRef size:NSZeroSize];

  NSData *tiffData = [sdfImage TIFFRepresentation];
  NSString *expandedPath = [[NSString stringWithUTF8String:path] stringByExpandingTildeInPath];
  [tiffData writeToFile:expandedPath atomically:YES];

  CGImageRelease(imageRef);
  CGContextRelease(context);
  CGColorSpaceRelease(colorSpace);
  free(imageData);
}

void fontAtlasFree(struct FontAtlas fontAtlas) {
  free(fontAtlas.imageData);
  free(fontAtlas.glyphDescriptors.topLeftTexCoords);
  free(fontAtlas.glyphDescriptors.bottomRightTexCoords);
}

void testStringRasterization(const char *text) {
  CGSize outCtxSize = CGSizeMake(300, 300);
  CGColorSpaceRef outColorSpace = CGColorSpaceCreateDeviceGray();
  CGContextRef outCtx = CGBitmapContextCreate(NULL, outCtxSize.width, outCtxSize.height,
                                              8, 0, outColorSpace, kCGImageAlphaNone);
  CGContextSetInterpolationQuality(outCtx, kCGInterpolationNone);
  CGContextSetShouldAntialias(outCtx, false);

  const size_t atlasWidth = 4096;
  const size_t atlasHeight = 4096;
  struct FontAtlas fontAtlas = createAtlasForFont("Menlo", atlasWidth, atlasHeight);
  CGColorSpaceRef atlasColorSpace = CGColorSpaceCreateDeviceGray();
  CGBitmapInfo atlasBitmapInfo = (kCGBitmapAlphaInfoMask & kCGImageAlphaNone);
  CGContextRef atlasCtx = CGBitmapContextCreate(fontAtlas.imageData,
                                               atlasWidth,
                                               atlasHeight,
                                               8,
                                               atlasWidth,
                                               atlasColorSpace,
                                               atlasBitmapInfo);
  CGContextTranslateCTM(atlasCtx, 0, atlasHeight);
  CGContextScaleCTM(atlasCtx, 1, -1);
  CGImageRef atlasImageRef = CGBitmapContextCreateImage(atlasCtx);
  
  NSDictionary *attributes = @{NSFontAttributeName: [NSFont fontWithName:@"Menlo" size:16]};
  NSAttributedString *attributedString =
    [[NSAttributedString alloc] initWithString:[NSString stringWithUTF8String:text]
                                    attributes:attributes];

  CTFramesetterRef framesetter =
    CTFramesetterCreateWithAttributedString((CFAttributedStringRef)attributedString);
  CGPathRef path = CGPathCreateWithRect(CGRectMake(0, 0, 300, 300), NULL);
  CTFrameRef frame = CTFramesetterCreateFrame(framesetter,
                                              CFRangeMake(0, [attributedString length]),
                                              path,
                                              NULL);
  CFArrayRef lines = CTFrameGetLines(frame);
  CGPoint lineOrigins[CFArrayGetCount(lines)];
  CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), lineOrigins);

  CGPoint glyphPositionOut = CGPointMake(0, 100);
  
  for (CFIndex lineIndex=0; lineIndex<CFArrayGetCount(lines); ++lineIndex) {
    CTLineRef line = CFArrayGetValueAtIndex(lines, lineIndex);
    NSArray *runs = (NSArray *)CTLineGetGlyphRuns(line);

    for (id runObj in runs) {
      CTRunRef run = (__bridge CTRunRef)runObj;
      CFIndex glyphCount = CTRunGetGlyphCount(run);
      CGGlyph glyphs[glyphCount];
      CGPoint glyphPositions[glyphCount];
      CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphs);
      CTRunGetPositions(run, CFRangeMake(0, 0), glyphPositions);

      for (CFIndex glyphIndex=0; glyphIndex<glyphCount; ++glyphIndex) {
        CGGlyph glyph = glyphs[glyphIndex];

        CGPoint topLeft = fontAtlas.glyphDescriptors.topLeftTexCoords[glyph];
        CGPoint bottomRight = fontAtlas.glyphDescriptors.bottomRightTexCoords[glyph];
        CGFloat width = atlasWidth * (bottomRight.x - topLeft.x);
        CGFloat height = atlasHeight * (bottomRight.y - topLeft.y);
        CGFloat originX = atlasWidth * topLeft.x;
        CGFloat originY = atlasHeight * topLeft.y;
        CGRect glyphAtlasFrame = CGRectMake(originX, originY, width, height);

        CGImageRef glyphImageRef = CGImageCreateWithImageInRect(atlasImageRef, glyphAtlasFrame);
        CGContextDrawImage(outCtx,
                           CGRectMake(glyphPositionOut.x,
                                      glyphPositionOut.y,
                                      CGRectGetWidth(glyphAtlasFrame),
                                      CGRectGetHeight(glyphAtlasFrame)),
                           glyphImageRef);
        CGImageRelease(glyphImageRef);

        glyphPositionOut.x += CGRectGetWidth(glyphAtlasFrame);
      }
    }
  }

  CGImageRef outImageRef = CGBitmapContextCreateImage(outCtx);
  NSImage *outImage = [[NSImage alloc] initWithCGImage:outImageRef size:NSZeroSize];
  NSData *tiffData = [outImage TIFFRepresentation];
  const char *filePath = "~/Desktop/text.tiff";
  NSString *expandedPath = [[NSString stringWithUTF8String:filePath] stringByExpandingTildeInPath];
  [tiffData writeToFile:expandedPath atomically:YES];
  printf("text '%s' saved to %s\n", text, filePath);

  // --- Cleanup

  CFRelease(frame);
  CFRelease(framesetter);
  CFRelease(path);
  
  CGImageRelease(atlasImageRef);
  CGContextRelease(atlasCtx);
  CGColorSpaceRelease(atlasColorSpace);
  CGImageRelease(outImageRef);
  CGContextRelease(outCtx);
  CGColorSpaceRelease(outColorSpace);
  
  fontAtlasFree(fontAtlas);
}

#ifdef COMPILE_AS_TEST
int main() {
  const size_t atlasWidth = 4096;
  const size_t atlasHeight = 4096;
  
  struct FontAtlas fontAtlas = createAtlasForFont("Menlo", atlasWidth, atlasHeight);

  const char *fontAtlasImageFilePath = "~/Desktop/fontAtlas.tiff";
  writeFontAtlasToTiffFile(fontAtlas.imageData, atlasWidth, atlasHeight,
                           fontAtlasImageFilePath);
  printf("font atlas saved to %s\n", fontAtlasImageFilePath);
  
  float *sdf = createSdfForGrayscaleImage(fontAtlas.imageData, atlasWidth, atlasHeight);

  const char *sdfImageFilePath = "~/Desktop/sdfFontAtlas.tiff";
  writeSdfToTiffFile(sdf, atlasWidth, atlasHeight, sdfImageFilePath);
  printf("sdf saved to %s\n", sdfImageFilePath);
  
  fontAtlasFree(fontAtlas);
  free(sdf);

  testStringRasterization("Hello world!");
  
  sleep(20);
  return 0;
}
#endif
