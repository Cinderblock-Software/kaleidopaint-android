// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

@file:Suppress("NOTHING_TO_INLINE")

package com.cinderblocksoftware.kaleidopaint.geometry

import kotlin.math.sqrt

//	Small vectors and matrices
//
//	KaleidoPaint's maths is written against Apple's simd library.
//	The types below stand in for the handful of simd types it uses,
//	with the same conventions, so that the translated code
//	can keep the shape of the original:
//
//		Double2			SIMD2<Double>
//		Int2			SIMD2<Int>
//		Double3			SIMD3<Double>
//		Float2			SIMD2<Float32>
//		Float4			SIMD4<Float16>	(widened to Float32)
//		Double2x2		simd_double2x2
//		Double3x3		simd_double3x3
//		Double3x2		simd_double3x2	(3 columns, 2 rows)
//		Double4x2		simd_double4x2	(4 columns, 2 rows)
//
//	As in simd,
//
//	  -	a matrix is built from its columns,
//	  -	m[i] is column i and m[i][j] is row j of column i,
//	  -	matrix * vector is the right-to-left matrix action,
//		that is, the sum of the matrix's columns
//		weighted by the vector's components.
//
//	Vectors and matrices are immutable values, as they are in Swift,
//	with one exception:  Double4x2 holds a spline arc's coefficients ξ,
//	which computeCubicSpline() writes one component at a time.

// MARK: -
// MARK: Vectors

class Double2(val x: Double, val y: Double) {

    constructor(x: Number, y: Number) : this(x.toDouble(), y.toDouble())

    constructor(v: Int2) : this(v.x.toDouble(), v.y.toDouble())

    operator fun get(index: Int): Double =
        when (index) {
            0 -> x
            1 -> y
            else -> throw IndexOutOfBoundsException("Double2 has no component $index")
        }

    operator fun plus(v: Double2) = Double2(x + v.x, y + v.y)

    operator fun minus(v: Double2) = Double2(x - v.x, y - v.y)

    operator fun unaryMinus() = Double2(-x, -y)

    operator fun times(s: Double) = Double2(x * s, y * s)

    operator fun div(s: Double) = Double2(x / s, y / s)

    //	Compare components the way Swift's == does, as IEEE numbers,
    //	so that (-0.0, 0.0) equals (0.0, 0.0).
    override fun equals(other: Any?): Boolean = other is Double2 && x == other.x && y == other.y

    override fun hashCode(): Int = 31 * (x + 0.0).hashCode() + (y + 0.0).hashCode()

    override fun toString(): String = "($x, $y)"

    companion object {
        val zero = Double2(0.0, 0.0)
    }
}

inline operator fun Double.times(v: Double2) = Double2(this * v.x, this * v.y)

fun length(v: Double2): Double = sqrt(v.x * v.x + v.y * v.y)

fun normalize(v: Double2): Double2 = v * (1.0 / sqrt(v.x * v.x + v.y * v.y))

fun floor(v: Double2) = Double2(kotlin.math.floor(v.x), kotlin.math.floor(v.y))

class Double3(val x: Double, val y: Double, val z: Double) {

    constructor(x: Number, y: Number, z: Number) : this(x.toDouble(), y.toDouble(), z.toDouble())

    constructor(xy: Double2, z: Double) : this(xy.x, xy.y, z)

    operator fun get(index: Int): Double =
        when (index) {
            0 -> x
            1 -> y
            2 -> z
            else -> throw IndexOutOfBoundsException("Double3 has no component $index")
        }

    operator fun plus(v: Double3) = Double3(x + v.x, y + v.y, z + v.z)

    operator fun minus(v: Double3) = Double3(x - v.x, y - v.y, z - v.z)

    operator fun times(s: Double) = Double3(x * s, y * s, z * s)

    operator fun div(s: Double) = Double3(x / s, y / s, z / s)

    override fun equals(other: Any?): Boolean =
        other is Double3 && x == other.x && y == other.y && z == other.z

    override fun hashCode(): Int =
        31 * (31 * (x + 0.0).hashCode() + (y + 0.0).hashCode()) + (z + 0.0).hashCode()

    override fun toString(): String = "($x, $y, $z)"
}

inline operator fun Double.times(v: Double3) = Double3(this * v.x, this * v.y, this * v.z)

//	SIMD2<Int>
data class Int2(val x: Int, val y: Int) {

    operator fun get(index: Int): Int =
        when (index) {
            0 -> x
            1 -> y
            else -> throw IndexOutOfBoundsException("Int2 has no component $index")
        }

    companion object {
        val zero = Int2(0, 0)
    }
}

//	Single-precision vectors, for handing vertices and colours to the GPU.

data class Float2(val x: Float, val y: Float) {

    constructor(v: Double2) : this(v.x.toFloat(), v.y.toFloat())

    operator fun get(index: Int): Float =
        when (index) {
            0 -> x
            1 -> y
            else -> throw IndexOutOfBoundsException("Float2 has no component $index")
        }
}

data class Float4(val x: Float, val y: Float, val z: Float, val w: Float) {

    operator fun get(index: Int): Float =
        when (index) {
            0 -> x
            1 -> y
            2 -> z
            3 -> w
            else -> throw IndexOutOfBoundsException("Float4 has no component $index")
        }
}

// MARK: -
// MARK: Matrices

class Double2x2(val column0: Double2, val column1: Double2) {

    operator fun get(column: Int): Double2 =
        when (column) {
            0 -> column0
            1 -> column1
            else -> throw IndexOutOfBoundsException("Double2x2 has no column $column")
        }

    //	Returns a copy of this matrix with one column replaced,
    //	for translating Swift's  m[i] = v .
    fun withColumn(column: Int, v: Double2): Double2x2 =
        when (column) {
            0 -> Double2x2(v, column1)
            1 -> Double2x2(column0, v)
            else -> throw IndexOutOfBoundsException("Double2x2 has no column $column")
        }

    val determinant: Double
        get() = column0.x * column1.y - column0.y * column1.x

    val transpose: Double2x2
        get() =
            Double2x2(
                Double2(column0.x, column1.x),
                Double2(column0.y, column1.y),
            )

    val inverse: Double2x2
        get() {
            val theFactor = 1.0 / determinant
            return Double2x2(
                Double2(column1.y * theFactor, -column0.y * theFactor),
                Double2(-column1.x * theFactor, column0.x * theFactor),
            )
        }

    //	right-to-left matrix action
    operator fun times(v: Double2) =
        Double2(
            column0.x * v.x + column1.x * v.y,
            column0.y * v.x + column1.y * v.y,
        )

    //	(this * m) acts by m first, then by this.
    operator fun times(m: Double2x2) = Double2x2(this * m.column0, this * m.column1)

    operator fun times(s: Double) = Double2x2(column0 * s, column1 * s)

    override fun equals(other: Any?): Boolean =
        other is Double2x2 && column0 == other.column0 && column1 == other.column1

    override fun hashCode(): Int = 31 * column0.hashCode() + column1.hashCode()

    override fun toString(): String = "[$column0, $column1]"

    companion object {
        val identity =
            Double2x2(
                Double2(1.0, 0.0),
                Double2(0.0, 1.0),
            )
    }
}

inline operator fun Double.times(m: Double2x2) = Double2x2(this * m.column0, this * m.column1)

class Double3x3(val column0: Double3, val column1: Double3, val column2: Double3) {

    operator fun get(column: Int): Double3 =
        when (column) {
            0 -> column0
            1 -> column1
            2 -> column2
            else -> throw IndexOutOfBoundsException("Double3x3 has no column $column")
        }

    //	Returns a copy of this matrix with one entry replaced,
    //	for translating Swift's  m[i][j] = a .
    fun with(column: Int, row: Int, value: Double): Double3x3 {
        fun replaced(v: Double3) =
            Double3(
                if (row == 0) value else v.x,
                if (row == 1) value else v.y,
                if (row == 2) value else v.z,
            )
        if (row !in 0..2) {
            throw IndexOutOfBoundsException("Double3x3 has no row $row")
        }
        return when (column) {
            0 -> Double3x3(replaced(column0), column1, column2)
            1 -> Double3x3(column0, replaced(column1), column2)
            2 -> Double3x3(column0, column1, replaced(column2))
            else -> throw IndexOutOfBoundsException("Double3x3 has no column $column")
        }
    }

    val determinant: Double
        get() =
            (column0.x * (column1.y * column2.z - column2.y * column1.z) -
                column1.x * (column0.y * column2.z - column2.y * column0.z) +
                column2.x * (column0.y * column1.z - column1.y * column0.z))

    val inverse: Double3x3
        get() {
            //	The inverse is the adjugate over the determinant.
            val a = column0
            val b = column1
            val c = column2
            val theFactor = 1.0 / determinant
            return Double3x3(
                Double3(
                    (b.y * c.z - c.y * b.z) * theFactor,
                    (c.y * a.z - a.y * c.z) * theFactor,
                    (a.y * b.z - b.y * a.z) * theFactor,
                ),
                Double3(
                    (c.x * b.z - b.x * c.z) * theFactor,
                    (a.x * c.z - c.x * a.z) * theFactor,
                    (b.x * a.z - a.x * b.z) * theFactor,
                ),
                Double3(
                    (b.x * c.y - c.x * b.y) * theFactor,
                    (c.x * a.y - a.x * c.y) * theFactor,
                    (a.x * b.y - b.x * a.y) * theFactor,
                ),
            )
        }

    //	right-to-left matrix action
    operator fun times(v: Double3) =
        Double3(
            column0.x * v.x + column1.x * v.y + column2.x * v.z,
            column0.y * v.x + column1.y * v.y + column2.y * v.z,
            column0.z * v.x + column1.z * v.y + column2.z * v.z,
        )

    //	(this * m) acts by m first, then by this.
    operator fun times(m: Double3x3) =
        Double3x3(this * m.column0, this * m.column1, this * m.column2)

    override fun equals(other: Any?): Boolean =
        other is Double3x3 &&
            column0 == other.column0 &&
            column1 == other.column1 &&
            column2 == other.column2

    override fun hashCode(): Int =
        31 * (31 * column0.hashCode() + column1.hashCode()) + column2.hashCode()

    override fun toString(): String = "[$column0, $column1, $column2]"

    companion object {
        val identity =
            Double3x3(
                Double3(1.0, 0.0, 0.0),
                Double3(0.0, 1.0, 0.0),
                Double3(0.0, 0.0, 1.0),
            )
    }
}

//	3 columns, 2 rows:  maps a Double3 to a Double2.
class Double3x2(val column0: Double2, val column1: Double2, val column2: Double2) {

    operator fun get(column: Int): Double2 =
        when (column) {
            0 -> column0
            1 -> column1
            2 -> column2
            else -> throw IndexOutOfBoundsException("Double3x2 has no column $column")
        }

    //	right-to-left matrix action
    operator fun times(v: Double3) =
        Double2(
            column0.x * v.x + column1.x * v.y + column2.x * v.z,
            column0.y * v.x + column1.y * v.y + column2.y * v.z,
        )

    override fun toString(): String = "[$column0, $column1, $column2]"
}

//	4 columns, 2 rows, and mutable (see the note at the top of this file).
//	Swift copies a simd_double4x2 on assignment;  use copy() where that matters.
class Double4x2 {

    private val itsEntries = DoubleArray(8) // 	column-major, initially all zero

    operator fun get(column: Int): Double2 {
        checkColumn(column)
        return Double2(itsEntries[2 * column + 0], itsEntries[2 * column + 1])
    }

    //	For translating Swift's  m[i][j] = a .
    operator fun set(column: Int, row: Int, value: Double) {
        checkColumn(column)
        if (row !in 0..1) {
            throw IndexOutOfBoundsException("Double4x2 has no row $row")
        }
        itsEntries[2 * column + row] = value
    }

    fun copy(): Double4x2 {
        val theCopy = Double4x2()
        itsEntries.copyInto(theCopy.itsEntries)
        return theCopy
    }

    private fun checkColumn(column: Int) {
        if (column !in 0..3) {
            throw IndexOutOfBoundsException("Double4x2 has no column $column")
        }
    }

    override fun toString(): String = "[${this[0]}, ${this[1]}, ${this[2]}, ${this[3]}]"
}
