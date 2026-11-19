//	KaleidoPaintWallpaperGroup.swift
//
//	© 2026 by Jeff Weeks
//	See TermsOfUse.txt

import simd
import SwiftUI


//	The 17 wallpaper groups
//
//	The names are based on Conway's orbifold notation.
//		○ = handle			(written as 'O' in names below)
//		× = crosscap		(written as 'X' in name below)
//		* = mirror boundary	(written as 'S' for "star" in names below)
//
enum WallpaperGroup: String, CaseIterable, Identifiable {

	case wpgO		= "○"
	case wpg2222	= "2222"
	case wpg333		= "333"
	case wpg442		= "442"
	case wpg632		= "632"
	case wpgS2222	= "*2222"
	case wpgS333	= "*333"
	case wpgS442	= "*442"
	case wpgS632	= "*632"
	case wpg22S		= "22*"
	case wpg2S22	= "2*22"
	case wpg3S3		= "3*3"
	case wpg4S2		= "4*2"
	case wpgSS		= "**"
	case wpg22X		= "22×"
	case wpgSX		= "*×"
	case wpgXX		= "××"
	
	var id: String { self.rawValue }
	
	var orbifoldName: String {
		
		return self.rawValue
	}
	
	var IUCName: String {
		
		switch self {
		
		case .wpgO:		return "p1"
		case .wpg2222:	return "p2"
		case .wpg333:	return "p3"
		case .wpg442:	return "p4"
		case .wpg632:	return "p6"
		case .wpgS2222:	return "pmm"
		case .wpgS333:	return "p3m1"
		case .wpgS442:	return "p4m"
		case .wpgS632:	return "p6m"
		case .wpg22S:	return "pmg"
		case .wpg2S22:	return "cmm"
		case .wpg3S3:	return "p31m"
		case .wpg4S2:	return "p4g"
		case .wpgSS:	return "pm"
		case .wpg22X:	return "pgg"
		case .wpgSX:	return "cm"
		case .wpgXX:	return "pg"
		
		}
	}
	
	var torusGroup: TorusGroup {
	
		switch self {

		case .wpgO:

			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0)
				],
				itsUnitCellShapeConstraints: [],
				itsMirrorSegments: [],
				itsGyrationPoints: [],
				itsGlideReflectionSegments: []
			)

		case .wpg2222:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated6)
				],
				itsUnitCellShapeConstraints: [],
				itsMirrorSegments: [],
				itsGyrationPoints: [
					SIMD2<Double>(0.0, 0.0),
					SIMD2<Double>(0.0, 0.5),
					SIMD2<Double>(0.5, 0.0),
					SIMD2<Double>(0.5, 0.5)
				],
				itsGlideReflectionSegments: []
			)
			
		case .wpg333:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in 333
						]),
						itsColor: gColorRotated4),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in 333
						]),
						itsColor: gColorRotated8)
				],
				itsUnitCellShapeConstraints: [.rhombus, .angle_2π_over_6],
				itsMirrorSegments: [],
				itsGyrationPoints: [
					SIMD2<Double>(  0.0,     0.0  ),
					SIMD2<Double>(1.0/3.0, 1.0/3.0),
					SIMD2<Double>(2.0/3.0, 2.0/3.0)
				],
				itsGlideReflectionSegments: []
			)
			
		case .wpg442:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated3),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated9)
				],
				itsUnitCellShapeConstraints: [.rhombus, .angle_2π_over_4],
				itsMirrorSegments: [],
				itsGyrationPoints: [
					SIMD2<Double>(0.0, 0.0),
					SIMD2<Double>(0.0, 0.5),
					SIMD2<Double>(0.5, 0.5)
				],
				itsGlideReflectionSegments: []
			)
			
		case .wpg632:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>( 1, -1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in 632
						]),
						itsColor: gColorRotated2),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in 632
						]),
						itsColor: gColorRotated4),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>( 0,  1,  1)		//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in 632
						]),
						itsColor: gColorRotated8),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>(-1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in 632
						]),
						itsColor: gColorRotated10)
				],
				itsUnitCellShapeConstraints: [.rhombus, .angle_2π_over_6],
				itsMirrorSegments: [],
				itsGyrationPoints: [
					SIMD2<Double>(  0.0,     0.0  ),
					SIMD2<Double>(1.0/3.0, 1.0/3.0),
					SIMD2<Double>(  0.5,     0.5  )
				],
				itsGlideReflectionSegments: []
			)
			
		case .wpgS2222:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated6)
				],
				itsUnitCellShapeConstraints: [.angle_2π_over_4],
				itsMirrorSegments: [
					(SIMD2<Double>(0.0, 0.0), SIMD2<Double>(0.5, 0.0)),
					(SIMD2<Double>(0.5, 0.0), SIMD2<Double>(0.5, 0.5)),
					(SIMD2<Double>(0.5, 0.5), SIMD2<Double>(0.0, 0.5)),
					(SIMD2<Double>(0.0, 0.5), SIMD2<Double>(0.0, 0.0))
				],
				itsGyrationPoints: [],
				itsGlideReflectionSegments: []
			)
			
		case .wpgS333:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in *333
						]),
						itsColor: gColorRotated4),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in *333
						]),
						itsColor: gColorRotated8),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected2),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in *333
						]),
						itsColor: gColorReflected6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in *333
						]),
						itsColor: gColorReflected10)
				],
				itsUnitCellShapeConstraints: [.rhombus, .angle_2π_over_6],
				itsMirrorSegments: [
					(SIMD2<Double>(1.0/3.0, 1.0/3.0), SIMD2<Double>(2.0/3.0, 2.0/3.0)),
					(SIMD2<Double>(2.0/3.0, 2.0/3.0), SIMD2<Double>(  0.0,     1.0  )),
					(SIMD2<Double>(  0.0,     1.0  ), SIMD2<Double>(1.0/3.0, 1.0/3.0))
				],
				itsGyrationPoints: [],
				itsGlideReflectionSegments: []
			)
			
		case .wpgS442:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated3),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated9),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected3),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected9)
				],
				itsUnitCellShapeConstraints: [.rhombus, .angle_2π_over_4],
				itsMirrorSegments: [
					(SIMD2<Double>(0.0, 0.0), SIMD2<Double>(0.5, 0.0)),
					(SIMD2<Double>(0.5, 0.0), SIMD2<Double>(0.5, 0.5)),
					(SIMD2<Double>(0.5, 0.5), SIMD2<Double>(0.0, 0.0))
				],
				itsGyrationPoints: [],
				itsGlideReflectionSegments: []
			)
			
		case .wpgS632:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>( 1, -1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in *632
						]),
						itsColor: gColorRotated2),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in *632
						]),
						itsColor: gColorRotated4),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in *632
						]),
						itsColor: gColorRotated8),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>(-1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in *632
						]),
						itsColor: gColorRotated10),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>(-1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in *632
						]),
						itsColor: gColorReflected0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected2),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1, -1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in *632
						]),
						itsColor: gColorReflected4),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in *632
						]),
						itsColor: gColorReflected6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected8),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in *632
						]),
						itsColor: gColorReflected10),
				],
				itsUnitCellShapeConstraints: [.rhombus, .angle_2π_over_6],
				itsMirrorSegments: [
					(SIMD2<Double>(  0.0,     0.0  ), SIMD2<Double>(  0.5,     0.0  )),
					(SIMD2<Double>(  0.5,     0.0  ), SIMD2<Double>(1.0/3.0, 1.0/3.0)),
					(SIMD2<Double>(1.0/3.0, 1.0/3.0), SIMD2<Double>(  0.0,     0.0  ))
				],
				itsGyrationPoints: [],
				itsGlideReflectionSegments: []
			)
			
		case .wpg22S:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1, 0.5, 1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in 22*
						]),
						itsColor: gColorRotated6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1,-0.5, 1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in 22*
						]),
						itsColor: gColorReflected6)
				],
				itsUnitCellShapeConstraints: [.angle_2π_over_4],
				itsMirrorSegments: [
					(SIMD2<Double>(0.0, 0.0), SIMD2<Double>(0.5, 0.0)),
					(SIMD2<Double>(0.0, 0.5), SIMD2<Double>(0.5, 0.5))
				],
				itsGyrationPoints: [
					SIMD2<Double>(0.00, 0.25),
					SIMD2<Double>(0.50, 0.25)
				],
				itsGlideReflectionSegments: []
			)
			
		case .wpg2S22:

			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected6)
				],
				itsUnitCellShapeConstraints: [.rhombus],
				itsMirrorSegments: [
					(SIMD2<Double>(0.0, 0.0), SIMD2<Double>(0.5, 0.5)),
					(SIMD2<Double>(1.0, 0.0), SIMD2<Double>(0.5, 0.5))
				],
				itsGyrationPoints: [
					SIMD2<Double>(0.5, 0.0)
				],
				itsGlideReflectionSegments: []
			)
			
		case .wpg3S3:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in 3*3
						]),
						itsColor: gColorRotated4),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in 3*3
						]),
						itsColor: gColorRotated8),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 1, -1,  0),
							SIMD3<Double>(-1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in 3*3
						]),
						itsColor: gColorReflected0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  1,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1, -1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0, 1)
														//	which is the best we can do in 3*3
						]),
						itsColor: gColorReflected4),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected8)
				],
				itsUnitCellShapeConstraints: [.rhombus, .angle_2π_over_6],
				itsMirrorSegments: [
					(SIMD2<Double>(0.0, 0.0), SIMD2<Double>(1.0, 0.0))
				],
				itsGyrationPoints: [
					SIMD2<Double>(1.0/3.0, 1.0/3.0)
				],
				itsGlideReflectionSegments: []
			)
			
		case .wpg4S2:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 1,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated3),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated9),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,   0,  0),
							SIMD3<Double>( 0,  -1,  0),
							SIMD3<Double>(-0.5, 0.5, 1)	//	maps (0.5, 0.5, 1) ↦ (0, 0, 1)
														//	which is the best we can do in 4*2
						]),
						itsColor: gColorReflected0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,   1,  0),
							SIMD3<Double>( 1,   0,  0),
							SIMD3<Double>(-0.5,-0.5,1)	//	maps (0.5, 0.5, 1) ↦ (0, 0, 1)
														//	which is the best we can do in 4*2
						]),
						itsColor: gColorReflected3),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,   0,  0),
							SIMD3<Double>( 0,   1,  0),
							SIMD3<Double>(0.5,-0.5, 1)	//	maps (0.5, 0.5, 1) ↦ (0, 0, 1)
														//	which is the best we can do in 4*2
						]),
						itsColor: gColorReflected6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  -1,  0),
							SIMD3<Double>(-1,   0,  0),
							SIMD3<Double>(0.5, 0.5, 1)	//	maps (0.5, 0.5, 1) ↦ (0, 0, 1)
														//	which is the best we can do in 4*2
						]),
						itsColor: gColorReflected9),
				],
				itsUnitCellShapeConstraints: [.rhombus, .angle_2π_over_4],
				itsMirrorSegments: [
					(SIMD2<Double>(0.5, 0.0), SIMD2<Double>(0.0, 0.5))
				],
				itsGyrationPoints: [
					SIMD2<Double>(0.0, 0.0)
				],
				itsGlideReflectionSegments: []
			)
			
		case .wpgSS:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 0,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected0)
				],
				itsUnitCellShapeConstraints: [.angle_2π_over_4],
				itsMirrorSegments: [
					(SIMD2<Double>(0.0, 0.0), SIMD2<Double>(1.0, 0.0)),
					(SIMD2<Double>(0.0, 0.5), SIMD2<Double>(1.0, 0.5))
				],
				itsGyrationPoints: [],
				itsGlideReflectionSegments: []
			)
			
		case .wpg22X:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>( 1,  1,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorRotated6),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>(-0.5,0.5,1)	//	maps (0.5, 0.5, 1) ↦ (0, 0, 1)
														//	which is the best we can do in 22×
						]),
						itsColor: gColorReflected0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>(-1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>(0.5,-0.5,1)	//	maps (0.5, 0.5, 1) ↦ (0, 0, 1)
														//	which is the best we can do in 22×
						]),
						itsColor: gColorReflected6)
				],
				itsUnitCellShapeConstraints: [.angle_2π_over_4],
				itsMirrorSegments: [],
				itsGyrationPoints: [
					SIMD2<Double>(0.0, 0.0),
					SIMD2<Double>(0.5, 0.0)
				],
				itsGlideReflectionSegments: [
					(SIMD2<Double>(0.25, 0.25), SIMD2<Double>(0.75, 0.25))
				//	Show only one set of glide axes, to make it clear
				//	how the symmetry group's structure relates
				//	to its name in orbifold notation.
				//	(SIMD2<Double>(0.25, 0.25), SIMD2<Double>(0.25, 0.75))
				]
			)
			
		case .wpgSX:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  0,  1)	//	maps (0.5, 0.5, 1) ↦ (0.5, 0.5, 1)
						]),
						itsColor: gColorReflected0)
				],
				itsUnitCellShapeConstraints: [.rhombus],
				itsMirrorSegments: [
					(SIMD2<Double>(0.0, 0.0), SIMD2<Double>(1.0, 1.0))
				],
				itsGyrationPoints: [],
				itsGlideReflectionSegments: [
					(SIMD2<Double>(0.5, 0.0), SIMD2<Double>(1.0, 0.5))
				]
			)
			
		case .wpgXX:
		
			return TorusGroup(
				itsElements: [
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0,  1,  0),
							SIMD3<Double>( 0,  0,  1)
						]),
						itsColor: gColorRotated0),
					TorusGroupElement(
						itsMatrix: simd_double3x3([
							SIMD3<Double>( 1,  0,  0),
							SIMD3<Double>( 0, -1,  0),
							SIMD3<Double>(-0.5, 1, 1)	//	maps (0.5, 0.5, 1) ↦ (0, 0.5, 1)
														//	which is the best we can do in ××
						]),
						itsColor: gColorReflected0)
				],
				itsUnitCellShapeConstraints: [.angle_2π_over_4],
				itsMirrorSegments: [],
				itsGyrationPoints: [],
				itsGlideReflectionSegments: [
					(SIMD2<Double>(0.0, 0.0), SIMD2<Double>(0.5, 0.0)),
					(SIMD2<Double>(0.0, 0.5), SIMD2<Double>(0.5, 0.5))
				]
			)
			
		}
	}
}

//	Unit cells
//
//	A wallpaper pattern is a discrete group of isometries
//	of the Euclidean plane.  Let
//
//		E² = the Euclidean plane
//		G  = a given wallpaper group
//		H  = the subgroup of G consisting of all translations
//		Q  = the quotient orbifold E²/G
//		T  = the quotient torus E²/H
//
//	Because H is a subgroup of G, it follows that T covers Q.
//
//	Conceptually, KaleidoPaint thinks of a wallpaper pattern in terms
//	of the quotient orbifold Q.  For convenience, though,
//	KaleidoPaint works mainly with the quotient torus T.
//
//	Cutting the quotient torus open along two transverse geodesics
//	gives a parallelogram known as a "unit cell".
//	The Wikipedia article
//
//		en.wikipedia.org/wiki/Wallpaper_group
//
//	shows unit cells for all 17 wallpaper groups
//	(see the diagrams in the right-hand column)
//	along with excellent real-life photos of each pattern.
//
//	At run time, KaleidoPaint keeps a given drawing's unit cell,
//	realized as a Metal texture object.

//	More on unit cells
//
//	You don't need to read the following theoretical discussion
//	of unit cells to understand the code, but you may find it interesting,
//	especially if you're a mathematician.
//
//	Recall from above that
//
//		E² = the Euclidean plane
//		G  = a given wallpaper group
//		H  = the subgroup of G consisting of all translations
//		Q  = the quotient orbifold E²/G
//		T  = the quotient torus E²/H
//
//	Because H is a subgroup of G, it follows that T covers Q.
//
//	Intuitive definition of a "regular covering".
//	Draw some figure in the plane -- a fish, say --
//	and draw all its images under the action
//	of the wallpaper group G.
//	Also draw its (lone) image in the quotient orbifold Q,
//	and its (several) images in the quotient torus.
//	To say that T is a regular covering of Q means
//	means that for any two fish f0 and f1 in T,
//	there's a fish-respecting isometry of T taking f0 to f1.
//
//	Proposition.  T is a regular covering of Q.
//
//	Proof.  Each point of T is an equivalence class
//	[p] = {h(p) | h ∈ H} for some point p ∈ E².
//	To prove that T is a regular covering of Q,
//	we need to show that for any point p ∈ E² and any
//	symmetry g ∈ G, there exists an isometry
//	of the quotient torus T taking [p] to [g(p)].
//	The obvious candidate is, of course, g itself.
//
//	The first thing we need to check is that g gives
//	a well-defined action on the quotient torus T.
//	For any point [p'] ∈ T, we get
//
//		g([p'])	= g({h(p') | h ∈ H})			(1)
//				= {g(h(p')) | h ∈ H}			(2)
//				= {(g∘h)(p') | h ∈ H}			(3)
//				= {(g∘h∘g⁻¹∘g)(p') | h ∈ H}		(4)
//				= {(h'∘g)(p') | h' ∈ H}			(5)
//				= {(h∘g)(p') | h ∈ H}			(6)
//				= {h(g(p')) | h ∈ H}			(7)
//				= [g(p')]						(8)
//
//	In words, g maps the equivalence class containing p'
//	onto the equivance class containing g(p').
//	Most the steps in the preceding derivation
//	follow directly from the definition of an equivalence class.
//	The one exception is the passage from line (4) to line (5),
//	replacing g∘h∘g⁻¹ with h', which follows from the fact
//	that H is a normal subgroup of G, as proved in the lemma below.
//
//	Now that we know that g gives a well-defined isometry
//	of the quotient torus T, it follows immediately
//	from the definition that g([p]) = [g(p)], as required.
//	Q.E.D.
//
//	Definition.  H is a normal subgroup of G iff gHg⁻¹ = H
//	for all g ∈ G.
//
//	Lemma.  The translation subgroup H is a normal subgroup
//	of the full wallpaper group G.
//
//	Informal proof of lemma.  Draw a picture.
//	You'll see that g∘h∘g⁻¹ is a translation whenever h is.
//
//	Formal proof of lemma.  Define a homomorphism from G
//	into the orthogonal group O(2) that captures
//	the rotational/reflectional component of each isometry
//	while discarding its translational part.
//	The translation subgroup H is the kernel of that homomorphism,
//	and is therefore a normal subgroup of G.
//
//	End of theoretical discussion.

//	In practical terms, we'll represent an isometry g
//	of the quotient torus T as a 3×3 integer matrix M.
//	Each such matrix M acts on a point (x,y) as
//
//		       (m00 m01 m02)
//		(x y 1)(m10 m11 m12)
//		       (m20 m21 m22)
//
//	or, equivalently, as the transpose of that product.
//
//	The unit cell has cyclic coordinates x and y:
//	each coordinate's fractional part is meaningful
//	but its integer part is not.  For example,
//	(0.75, 0.50) = (3.75, 1.50) = (-1.25, 8.50) modulo integers.
//	Because the matrix M has all integer entries,
//	adding or subracting integers from x and y
//	affects only the integer part of the product (x y 1)(M),
//	never it's fractional part.
//
//	Note that the each matrix M treats the unit cell as a square,
//	even though the unit cell typically will appear as a parallelogram
//	in the final drawing.
//
typealias TorusMatrix = simd_double3x3

//	For each wallpaper group, the TorusGroup provide
//	(among other things) a complete list of symmetries
//	of the quotient torus T.
struct TorusGroup {

	let itsElements: [TorusGroupElement]	//	symmetries of the unit cell

	let itsUnitCellShapeConstraints: ShapeConstraints

	let itsMirrorSegments: [(SIMD2<Double>, SIMD2<Double>)]	//	only one image of each
	let itsGyrationPoints: [SIMD2<Double>]					//	only one image of each
	let itsGlideReflectionSegments: [(SIMD2<Double>, SIMD2<Double>)]	//	only one image of each

	var itsRigidity: Rigidity {
		
		return itsUnitCellShapeConstraints.contains(.rhombus) ?
		(
			(	itsUnitCellShapeConstraints.contains(.angle_2π_over_4)
			 || itsUnitCellShapeConstraints.contains(.angle_2π_over_6) ) ?
			.rigid :
			.rhombic
			
		) :	//	not constrained to a rhombus
		(
			//	Note:  .angle_2π_over_6 never occurs with .rhombus
			itsUnitCellShapeConstraints.contains(.angle_2π_over_4) ?
			.rectangular :
			.fullyFlexible
		)
	}
}

//
//	In the language of the theoretical discussion (see above),
//	the TorusGroup structure provides one matrix M
//	for each symmetry of the quotient torus T that takes fish to fish.
//
//	How does one find the matrices for the TorusGroup?
//
//	Method #1.  ("pedestrian method")
//
//		Because the matrices are all defined
//		using the unit cell's internal ("square") coordinates,
//		to find the TorusGroup matrices, you can temporarily
//		convert to geometric coordinates.  For example,
//		to find the internally defined matrix for a 1/6 rotation,
//		map the square to a 60° rhombus, do the rotation,
//		and then map back (using left-to-right matrix actions here):
//
//			(map square) (  rotate   ) (map rhombus)
//			(to rhombus) ( 1/6 turn  ) ( to square )
//		=
//			(  1    0  ) (  1/2 √3/2 ) (  1    0   )
//			( 1/2 √3/2 ) (-√3/2  1/2 ) (-1/√3 2/√3 )
//		=
//			(  0  1 )
//			( -1  1 )
//
//		As discussed above, the fact that the final matrix has integer entries
//		means that its action is well defined on a torus:  it takes
//		each equivalence class of points (points whose corresponding
//		coordinates differ by integers) to another equivalent class
//		of points.
//
//	Method #2.  ("easy method")
//
//		Just stare at the picture, and see what a given symmetry
//		does to the two vectors u and v that define the parallelgram.
//		If the symmetry maps u to a*u + b*v, and maps v to c*u + d*v,
//		then matrix
//						( a  b )
//						( c  d )
//
//		represents the symmetry in internal coordinates.
//
//	In the preceding examples the translational component was trivial,
//	so I wrote just the 2×2 part of the matrix.  The third row and
//	third column would be those of the identity.
//
//	For a pure action on a torus, integer translational components
//	are of course pointless.  However, the matrices in gTorusGroup[]
//	include translational components chosen to map the fundamental square
//	[0,1]×[0,1] onto itself whenever possible.  When mapping onto itself
//	isn't possible, the translations have been chosen so that
//	the translated image extends to the left of the fundmental square,
//	below the fundamental square or below-left of the fundamental square,
//	but never above not to the right of it.  This ensures that
//	the translated image always falls within "2×2 block"
//	with coordinates [-1,1]×[-1,1], not merely within the larger
//	"3×3 block" with coordinates [-1,2]×[-1,2] that one might naively
//	expect to have to deal with.

struct TorusGroupElement {
	let itsMatrix: TorusMatrix
	let itsColor: LinearDisplayP3Color	//	for color-by-symmetry only
}

//	Imagine a fixed color circle, with colors {red, yellow, green, cyan, blue, magenta}
//	running counterclockwise around it.  Now imagine an "indicator arrow" that
//	points to red.  Just as you apply each torus group element
//	to the drawing's dots and curves, apply the same group element
//	to the indicator arrow.  For example, a counterclockwise 1/3 rotation
//	would move the indicator arrow from the red direction to the green direction;
//	all dots and curves drawn under the action of that rotation would be colored green.
//	Note that the rotations are interpreted relative to the final shape
//	of the unit cell;  for groups like 333 and 632 (with ShapeConstraints
//	.rhombus and .angle_2π_over_6) the unit cell is thus not a square
//	but a rhombus with angle π/3.
//
let gColorRotated0	= LinearDisplayP3Color(r: 1.00, g: 0.00, b: 0.00, a: 1.00)	//	 0/12 CCW rotation
let gColorRotated2	= LinearDisplayP3Color(r: 1.00, g: 1.00, b: 0.00, a: 1.00)	//	 2/12 CCW rotation
let gColorRotated3	= LinearDisplayP3Color(r: 0.50, g: 1.00, b: 0.00, a: 1.00)	//	 3/12 CCW rotation
let gColorRotated4	= LinearDisplayP3Color(r: 0.00, g: 1.00, b: 0.00, a: 1.00)	//	 4/12 CCW rotation
let gColorRotated6	= LinearDisplayP3Color(r: 0.00, g: 0.75, b: 0.75, a: 1.00)	//	 6/12 CCW rotation
let gColorRotated8	= LinearDisplayP3Color(r: 0.00, g: 0.00, b: 1.00, a: 1.00)	//	 8/12 CCW rotation
let gColorRotated9	= LinearDisplayP3Color(r: 0.60, g: 0.40, b: 1.00, a: 1.00)	//	 9/12 CCW rotation
let gColorRotated10	= LinearDisplayP3Color(r: 1.00, g: 0.00, b: 1.00, a: 1.00)	//	10/12 CCW rotation

//	Imagine factoring each reflection as the composition of some arbitrary
//	but fixed reflection followed by an appropriate rotation.
//	Each reflection color is a blend of 3/4 white
//	and 1/4 of the rotational color defined above.
//	Of course all that really matters here is that we have
//	some reasonable set of pastel colors for the rotated images.
//
let gColorReflected0	= LinearDisplayP3Color(r: 1.00, g: 0.75, b: 0.75, a: 1.00)	//	reflection followed by  0/12 CCW rotation
let gColorReflected2	= LinearDisplayP3Color(r: 1.00, g: 1.00, b: 0.75, a: 1.00)	//	reflection followed by  2/12 CCW rotation
let gColorReflected3	= LinearDisplayP3Color(r: 0.87, g: 1.00, b: 0.75, a: 1.00)	//	reflection followed by  3/12 CCW rotation
let gColorReflected4	= LinearDisplayP3Color(r: 0.75, g: 1.00, b: 0.75, a: 1.00)	//	reflection followed by  4/12 CCW rotation
let gColorReflected6	= LinearDisplayP3Color(r: 0.75, g: 0.94, b: 0.94, a: 1.00)	//	reflection followed by  6/12 CCW rotation
let gColorReflected8	= LinearDisplayP3Color(r: 0.75, g: 0.75, b: 1.00, a: 1.00)	//	reflection followed by  8/12 CCW rotation
let gColorReflected9	= LinearDisplayP3Color(r: 0.90, g: 0.85, b: 1.00, a: 1.00)	//	reflection followed by  9/12 CCW rotation
let gColorReflected10	= LinearDisplayP3Color(r: 1.00, g: 0.75, b: 1.00, a: 1.00)	//	reflection followed by 10/12 CCW rotation

//	A wallpaper group's unit cell may be constrained to be a rhombus
//	and/or to have angle exactly 2π/4 or 2π/6.
//
//		Note:  An OptionSet is essentially a bit field,
//		but with a Set interface.
//
struct ShapeConstraints: OptionSet {

	let rawValue: UInt8
	
	static let rhombus			= ShapeConstraints(rawValue: 1 << 0)
	static let angle_2π_over_4	= ShapeConstraints(rawValue: 1 << 1)
	static let angle_2π_over_6	= ShapeConstraints(rawValue: 1 << 2)
}

//	Some wallpaper groups have more flexibility than others.
enum Rigidity {

	//	The only fully flexible groups are ○ and 2222.
	//
	case fullyFlexible
	
	//	With the groups *2222, 22*, 22×, ** and ××,
	//	the unit cell is a rectangle.
	//
	case rectangular
	
	//	With the groups 2*22 and *×, the unit cell is a rhombus,
	//	with mirror lines running along the unit cell's diagonal(s).
	//	But the user will most likely perceive a rectangular cell
	//	with twice the area of the true unit cell.
	//	So we'll let the aspect ratio slider control the shape
	//	of that rectangular cell.
	//
	case rhombic
	
	//	The rigid groups are 333, *333, 3*3, 442, *442, 4*2, 632 and *632.
	//	KaleidoPaint suppresses the ShapeButton for rigid groups,
	//	so in principle we'll never receive a rigid group here.
	//
	case rigid
}



//	Shifts
//
//	Recall from the discussion titled "Unit cells" (see above)
//	that each wallpaper group G contains a subgroup H consisting
//	of all its translations, and that the quotient E²/H is a torus T.
//	Recall too from the discussion titled "More on unit cells" (also above)
//	that T is a regular covering of the quotient orbifold Q = E²/G.
//	That is, given any two copies of the motif (the "fish" in the language
//	of "More on unit cells") in T, there's a global motif-respecting isometry
//	of T taking one to the other.  Let's call the group of all such isometries
//	the "torus group".  Thus the quotient of the torus T under the action
//	of the torus group is the orbifold Q.
//
//	Some of the torus groups, for example those for 2222 and 442,
//	fix the point (0.5, 0.5).  In such groups, every symmetry
//	of the torus may be lifted to a symmetry of the universal cover
//	that maps the unit cell's fundamental square [0,1]×[0,1] onto itself.
//	By using such lifts, the vertex shader may transform a single primitive
//	under the action of the torus group, without worrying that any transformed images
//	might land outside the fundamental square [0,1]×[0,1].
//
//	Other torus groups, for example those for 333 and 632,
//	sometimes send (0.5, 0.5) to either (0,0), (0.5, 0) or (0, 0.5),
//	thus mapping the fundamental square [0,1]×[0,1] to an image
//	that partially overlaps the original (half in and half out).
//
//	Here's the original fundamental square:
//
//			+     +     +     +
//
//
//
//			+     +-----+     +
//			      |     |
//			      |     |
//			      |     |
//			+     +-----+     +
//
//
//
//			+     +     +     +
//
//	Here's its transformed image under the action of (a lift of)
//	a rotation from the torus group of 333:
//
//			+     +     +     +
//
//
//
//			+-----+     +     +								//
//			 \_    \_          								//
//			   \_    \_        								//
//			     \     \       								//
//			+     +-----+     +								//
//
//
//
//			+     +     +     +
//
//	(Note:  In drawing coordinates this fundamental square
//	becomes a fundamental rhombus and the transformation shown
//	is a rigid rotation.  The above illustrations show
//	the transformation in unit cell coordinates,
//	which do not respect the metric.)
//
//	The torus group for 333 is an example of the worst-case scenario:
//	the fundamental square's image not only extends beyond the original,
//	but it touches the far edge of the "next square over".
//
//	If all content began wholly within a single copy
//	of the fundamental square, it would be enough to draw 9 copies
//	of each transformed object, shifted by {-1, 0, +1} horizontally
//	and by {-1, 0, +1} vertically.  Content that landed outside
//	the central fundamental square when transformed by the torus group
//	would get translated back into the fundamental square by the shift.
//
//	For faster performance, the gTorusGroup[] array takes care to ensure
//	that transformed images spill only to the left and/or downward,
//	never rightward or upward.  So it's enough to apply the shifts {0, +1}
//	in each direction, for a total of only 2² = 4 shifts rather
//	than 3² = 9 shifts.
//
//	However, if we want to allow for content that might straddle
//	the edges of the central fundamental square, then we must apply
//	an extra shift in each direction, that is, shift by {-1, 0, +1, +2}
//	instead of just by {0, +1}, for a total of 4² = 16 translated images.
//
//
//	Safe region
//
//	To summarize, the vertex shader will first apply
//	an element of the torus group, and then apply a shift;
//	all content which then ends up in the fundamental square [0,1]×[0,1]
//	will get drawn.  The question is, what region in the original
//	untransformed plane is guaranteed to get drawn?  The answer
//	depends on the torus group, of course.
//
//
//	For the wallpaper group ○, which consists of pure translations only
//	and whose torus group is trivial, the whole 4×4 block is safe:
//
//			+∙∙∙∙∙+∙∙∙∙∙+∙∙∙∙∙+∙∙∙∙∙+
//			∙                       ∙
//			∙                       ∙
//			∙                       ∙
//			+     +     +-----+     +
//			∙           |     |     ∙
//			∙           |     |     ∙
//			∙           |     |     ∙
//			+     +     +-----+     +
//			∙                       ∙
//			∙                       ∙
//			∙                       ∙
//			+     +     +     +     +
//			∙                       ∙
//			∙                       ∙
//			∙                       ∙
//			+∙∙∙∙∙+∙∙∙∙∙+∙∙∙∙∙+∙∙∙∙∙+
//
//
//	For the wallpaper group *442, the torus group acts
//	with full dihedral symmetry on the fundamental square.
//	Some of those symmetries take the leftmost column and/or
//	the bottommost row from inside the 4×4 block to outside
//	the 4×4 block, thus any content within the leftmost column
//	or bottommost row gets lost.
//	Only the closest 3×3 block is safe:
//
//			+     +∙∙∙∙∙+∙∙∙∙∙+∙∙∙∙∙+
//			      ∙                 ∙
//			      ∙                 ∙
//			      ∙                 ∙
//			+     +     +-----+     +
//			      ∙     |     |     ∙
//			      ∙     |     |     ∙
//			      ∙     |     |     ∙
//			+     +     +-----+     +
//			      ∙                 ∙
//			      ∙                 ∙
//			      ∙                 ∙
//			+     +∙∙∙∙∙+∙∙∙∙∙+∙∙∙∙∙+
//
//
//
//			+     +     +     +     +
//
//	For the wallpaper groups 2222, 442, *2222, 2*22, ** and *×
//	the torus group acts on the fundamental square
//	with some subset of dihedral symmetry, so that
//	same 3×3 block is safe for those groups as well.
//
//	For the wallpaper groups 22× and 4*2, the torus group includes
//	glide reflections taking the point (1/2, 1/2) to (0,0).
//	Its safe region is a superset of the 3×3 block shown above.
//
//	For the wallpaper groups ×× and 22*, the torus group includes
//	symmetries taking (1/2, 1/2) to (0, 1/2) and/or
//	symmetries taking (1/2, 1/2) to (1/2, 0).
//	Again the safe region is a superset of the 3×3 block shown above.
//
//	For the wallpaper group 333, the torus group includes rotations
//	-- rigid in drawing coordinate but appearing skewed
//	in unit cell coordinates -- taking (1/2, 1/2) to (0, 1/2) or (1/2, 0).
//	Because of the skewing, two corners of the 3×3 block shown above
//	get mapped outside the desired 4×4 block, so the safe region
//	gets clipped to the hexagon
//
//			+     +∙∙∙∙∙+∙∙∙∙∙+     +
//			      ∙            ∙
//			      ∙              ∙
//			      ∙                ∙
//			+     +     +-----+     +
//			      ∙     |     |     ∙
//			      ∙     |     |     ∙
//			      ∙     |     |     ∙
//			+     +     +-----+     +
//			       ∙                ∙
//			         ∙              ∙
//			           ∙            ∙
//			+     +     +∙∙∙∙∙+∙∙∙∙∙+
//
//
//
//			+     +     +     +     +
//
//	For the wallpaper groups 632, *333, *632 and 3*3,
//	the torus group's safe region is that same hexagon.
//
//
//	Finally, to allow for a curve's finite width, and also
//	for the fact that a spline may bulge out slightly beyond
//	the points used to construct it, we'll need to inset
//	that safe region slightly to get a "padded safe region"
//
//			+     +∙∙∙∙∙+∙∙∙∙∙+     +
//			      ∙⋅⋅⋅⋅⋅⋅⋅⋅⋅⋅⋅⋅∙
//			      ∙⋅            ⋅∙
//			      ∙⋅              ⋅∙
//			+     +⋅    +-----+    ⋅+
//			      ∙⋅    |     |    ⋅∙
//			      ∙⋅    |     |    ⋅∙
//			      ∙⋅    |     |    ⋅∙
//			+     +⋅    +-----+    ⋅+
//			       ∙⋅              ⋅∙
//			         ∙⋅            ⋅∙
//			           ∙⋅⋅⋅⋅⋅⋅⋅⋅⋅⋅⋅⋅∙
//			+     +     +∙∙∙∙∙+∙∙∙∙∙+
//
//
//
//			+     +     +     +     +
//
//	To determine exactly how much padding is needed
//	one could in principle use the bounds on the UnitCellPlacement
//	to work out the maximum dimensions of an ellipse
//	corresponding to a dot whose radius is the maximal dot thickness,
//	but even that estimate wouldn't be 100% rigorous because
//	of the uncertainty in the exact path of a spline.
//	So...  let's just make a reasonable guess and hope for the best!
//
let gSafeRegionInset = 0.125

let gMinShift = -1
let gMaxShift = +2
let gNumShifts = (gMaxShift - gMinShift + 1) * (gMaxShift - gMinShift + 1)
