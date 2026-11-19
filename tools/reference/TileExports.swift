// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
import Foundation
import simd

func emitTileExports() {
    for (g, group) in WallpaperGroup.allCases.enumerated() {
        for variant in 0...1 {
            for (format, size) in [(1080,1781),(801,599)].enumerated() {
                let document=KaleidoPaintDocument()
                document.itsWallpaperGroup=group
                document.itsUnitCellPlacement=UnitCellPlacement(defaultForWallpaperGroup: group)
                if variant==1 {
                    switch group.torusGroup.itsRigidity {
                    case .fullyFlexible: document.setUnitCellShape(UnitCellShape(aspectRatio: 1.7,shear: 0.6))
                    case .rectangular: document.setUnitCellShape(UnitCellShape(aspectRatio: 1.6,shear: 0.0))
                    case .rhombic: document.setUnitCellShape(UnitCellShape(aspectRatio: 0.7,shear: 0.0))
                    case .rigid: break
                    }
                    document.itsUnitCellPlacement.transform(using: simd_double3x2(
                        SIMD2<Double>(0.9,0.2),SIMD2<Double>(-0.2,0.9),SIMD2<Double>(0.13,-0.21)))
                }
                let key="session.tile.\(g).\(variant).\(format)"
                func placement(_ suffix: String) {
                    let p=document.itsUnitCellPlacement
                    emit(key+suffix,doubles:[p.itsCorner[0],p.itsCorner[1],p.itsTranslations[0][0],p.itsTranslations[0][1],p.itsTranslations[1][0],p.itsTranslations[1][1]])
                }
                let (w,h)=document.prepareModelToExportTileableRectangle(availableWidthPx:size.0,availableHeightPx:size.1)
                emit(key+".size",ints:[w,h])
                placement(".placement")
                document.restoreModelAfterExportingTileableRectangle()
                placement(".restored")
            }
        }
    }
}
