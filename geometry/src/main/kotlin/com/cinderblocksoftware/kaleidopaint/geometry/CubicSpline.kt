// Ported from KaleidoPaintCubicSpline.swift (KaleidoPaint, © 2026 Jeff Weeks, GPLv2+).
// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

@file:Suppress("EnumEntryName", "LocalVariableName", "PropertyName")

package com.cinderblocksoftware.kaleidopaint.geometry

class CubicSpline {

    var itsNodes: MutableList<SplineNode> = mutableListOf()

    fun append(node: SplineNode) {
        itsNodes.add(node)
    }

    fun keepCenteredInUnitCell() {

        val theShift = computeShiftToKeepCenteredInUnitCell()
        applyShift(theShift)
    }

    fun computeShiftToKeepCenteredInUnitCell(): Double2 {

        //	If the user edits a curve so that it ends up running
        //	from, say, location (0.2, 1.6) to location (0.2, 1.9)
        //	in unit cell coordinates, we'll want to re-center it
        //	so that it runs from (0.2, 0.6) to location (0.2, 0.9)
        //	instead.  Such re-centering eliminates the risk that
        //	a curve will stray too far from the unit cell and
        //	get clipped.
        //
        //	Thanks to Francine Champagne for reporting this probem,
        //	that on rare occasions a few of her curves were
        //	getting needlessly clipped.

        val x = itsNodes.map() { node -> node.itsNodeLocation[0] }
        val y = itsNodes.map() { node -> node.itsNodeLocation[1] }

        val xMin = x.minOrNull() ?: 0.5
        val xMax = x.maxOrNull() ?: 0.5
        val xMid = 0.5 * (xMin + xMax)
        val xShift = round(0.5 - xMid)

        val yMin = y.minOrNull() ?: 0.5
        val yMax = y.maxOrNull() ?: 0.5
        val yMid = 0.5 * (yMin + yMax)
        val yShift = round(0.5 - yMid)

        return Double2(xShift, yShift)
    }

    fun applyShift(shift: Double2) {
        if (shift != Double2.zero) {
            for (theNode in itsNodes) {
                theNode.itsNodeLocation += shift
            }
        }
    }

    fun refreshParameterization() {

        //	CubicSpline represents a curve with possible corners.
        //	We split the curve into a sequence of zero or more arcs,
        //	with each arc running from one endpoint or corner
        //	to the next endpoint or corner.

        if (itsNodes.size == 1) {

            //	The curve has only one node, and therefore no arcs.
            //	Set ξ to zero just to be tidy.

            itsNodes[0].ξ = Double4x2()
        }

        if (itsNodes.size >= 2) {

            //	The curve has at least one arc.

            val theCurveStart = 0
            val theCurveEnd = itsNodes.size - 1

            var theArcStart = theCurveStart
            while (theArcStart < theCurveEnd) {

                var theArcEnd = theArcStart + 1

                while (
                    itsNodes[theArcEnd].itsNodeType == SplineNodeType.smooth &&
                        theArcEnd < theCurveEnd
                ) {

                    theArcEnd += 1
                }

                //	To draw a smooth arc (x(t), y(t)) in the plane,
                //	compute a spline for one coordinate (x or y) at a time.
                computeCubicSpline(
                    firstNode = theArcStart,
                    lastNode = theArcEnd,
                    coordinateIndex = 0,
                ) //	spline for x
                computeCubicSpline(
                    firstNode = theArcStart,
                    lastNode = theArcEnd,
                    coordinateIndex = 1,
                ) //	spline for y

                theArcStart = theArcEnd
            }
        }
    }

    private fun computeCubicSpline(
        firstNode: Int, // 	index of a SplineNode in itsNodes
        lastNode: Int, // 	index of a SplineNode in itsNodes
        coordinateIndex: Int, // 	0 (for x coordinate) or 1 (for y coordinate)
    ) {

        //	Within this documentation (but not within the code itself)
        //	imagine the nodes to be labelled with indices i = 0 … n.
        //	We'll define the spline in pieces, with piece i running
        //	from node i at time tᵢ to node i+1 at time tᵢ₊₁.
        //
        //	Note:  Although it's convenient to think of t as time
        //	and visualize a point moving along the curve,
        //	in reality t is a rough approximation of arc length.
        //
        //	The formula for piece i will be
        //
        //		        cᵢ₊₁ (tᵢ₊₁ - tᵢ)²   (t - tᵢ)³
        //		Sᵢ(t) = -----------------  ------------
        //		               6           (tᵢ₊₁ - tᵢ)³
        //
        //		          cᵢ (tᵢ₊₁ - tᵢ)²  (tᵢ₊₁ - t)³
        //			  + ------------------ ------------
        //		               6           (tᵢ₊₁ - tᵢ)³
        //
        //		                cᵢ₊₁ (tᵢ₊₁ - tᵢ)²   ( t   - tᵢ)
        //		      + (xᵢ₊₁ - ----------------- ) -----------
        //		                       6            (tᵢ₊₁ - tᵢ)
        //
        //		                 cᵢ  (tᵢ₊₁ - tᵢ)²   (tᵢ₊₁ - t )
        //		      + ( xᵢ  - ----------------- ) -----------
        //		                       6            (tᵢ₊₁ - tᵢ)
        //
        //	where t ranges from tᵢ to tᵢ₊₁.  The constants cᵢ (whose values we'll
        //	determine momentarily) tell the second derivative at each node.
        //
        //	It's immediately obvious that Sᵢ(t) runs from xᵢ to xᵢ₊₁ as required.
        //	We'd like the first and second derivatives to match as well.
        //
        //	The first two derivative of the spline function are
        //
        //		         cᵢ₊₁ (tᵢ₊₁ - tᵢ)²   (t - tᵢ)²        1
        //		S'ᵢ(t) = -----------------  ------------ -----------
        //		                2           (tᵢ₊₁ - tᵢ)² (tᵢ₊₁ - tᵢ)
        //
        //		           cᵢ (tᵢ₊₁ - tᵢ)²  (tᵢ₊₁ - t)²       1
        //			   - ------------------ ------------ -----------
        //		                2           (tᵢ₊₁ - tᵢ)² (tᵢ₊₁ - tᵢ)
        //
        //		                 cᵢ₊₁ (tᵢ₊₁ - tᵢ)²        1
        //		       + (xᵢ₊₁ - ----------------- ) -----------
        //		                        6            (tᵢ₊₁ - tᵢ)
        //
        //		                  cᵢ  (tᵢ₊₁ - tᵢ)²        1
        //		       - ( xᵢ  - ----------------- ) -----------
        //		                        6            (tᵢ₊₁ - tᵢ)
        //
        //		               (t - tᵢ)
        //		S"ᵢ(t) = cᵢ₊₁ -----------
        //		              (tᵢ₊₁ - tᵢ)
        //
        //		              (tᵢ₊₁ - t)
        //			   +  cᵢ  -----------
        //		              (tᵢ₊₁ - tᵢ)
        //
        //	It's immediately obvious that Sᵢ(t) has second derivative cᵢ at time tᵢ
        //	and second derivative cᵢ₊₁ at time tᵢ₊₁, as desired.  In particular,
        //	the second derivative at the end of segment i agrees with the second derivative
        //	at the beginning of segment i+1.
        //
        //	To get the first derivatives to agree at the nodes requires a little more effort.
        //	Setting
        //
        //		S'ᵢ(tᵢ₊₁) = S'ᵢ₊₁(tᵢ₊₁)
        //
        //	gives
        //
        //		  cᵢ₊₁ (tᵢ₊₁ - tᵢ)²      1
        //		  ----------------- -----------
        //		         2          (tᵢ₊₁ - tᵢ)
        //
        //		          cᵢ₊₁ (tᵢ₊₁ -  tᵢ )²        1
        //		+ (xᵢ₊₁ - ------------------- ) -----------
        //		                   6            (tᵢ₊₁ - tᵢ)
        //
        //		           cᵢ  (tᵢ₊₁ -  tᵢ )²        1
        //		- ( xᵢ  - ------------------- ) -----------
        //		                   6            (tᵢ₊₁ - tᵢ)
        //	=
        //		  cᵢ₊₁ (tᵢ₊₂ - tᵢ₊₁)²       1
        //		- ------------------- -------------
        //		         2            (tᵢ₊₂ - tᵢ₊₁)
        //
        //		          cᵢ₊₂ (tᵢ₊₂ - tᵢ₊₁)²        1
        //		+ (xᵢ₊₂ - ------------------- ) -------------
        //		                   6            (tᵢ₊₂ - tᵢ₊₁)
        //
        //		          cᵢ₊₁ (tᵢ₊₂ - tᵢ₊₁)²        1
        //		- (xᵢ₊₁ - ------------------- ) -------------
        //		                   6            (tᵢ₊₂ - tᵢ₊₁)
        //
        //	which simplifies to
        //
        //		    cᵢ   (tᵢ₊₁ - tᵢ)
        //		+ 2 cᵢ₊₁ (tᵢ₊₂ - tᵢ)
        //		+   cᵢ₊₂ (tᵢ₊₂ - tᵢ₊₁)
        //	=
        //		6 [ (xᵢ₊₂ - xᵢ₊₁) / (tᵢ₊₂ - tᵢ₊₁)
        //		  - (xᵢ₊₁ -  xᵢ ) / (tᵢ₊₁ -  tᵢ ) ]
        //
        //	We'll set c₀ = 0 and cₙ = 0 (this is the definition of a "natural spline")
        //	and then solve those n-1 linear equations for c₁ … cₙ₋₁, to insure
        //	that the first derivatives agree at all interior nodes.

        precondition(
            firstNode < lastNode,
            "Internal error:  spline must have at least two nodes",
        )

        //	Set default parameterizations ξ that connect
        //	each node to the next with a straight line,
        //	in case we return prematurely due to error.
        for (theNode in firstNode..(lastNode - 1)) {

            itsNodes[theNode].ξ[0, coordinateIndex] =
                itsNodes[theNode + 0].itsNodeLocation[coordinateIndex]

            itsNodes[theNode].ξ[1, coordinateIndex] =
                itsNodes[theNode + 1].itsNodeLocation[coordinateIndex]

            itsNodes[theNode].ξ[2, coordinateIndex] = 0.0

            itsNodes[theNode].ξ[3, coordinateIndex] = 0.0
        }

        //	How many nodes?
        val theNumNodes = (lastNode - firstNode) + 1

        //	Because firstNode < lastNode we know that theNumNodes ≥ 2,
        //	but the algorithm below requires that theNumNodes ≥ 3.
        //	In the case that theNumNodes == 2, the default
        //	straight-line parameterization (set above) is exactly what we want.
        //
        if (theNumNodes == 2) {
            return
        }

        //	Allocate temporary arrays.
        val Δt = DoubleArray(theNumNodes) // 	tᵢ₊₁ - tᵢ
        val Δx = DoubleArray(theNumNodes) // 	xᵢ₊₁ - xᵢ
        val rhs = DoubleArray(theNumNodes) // 	constant on right hand side of each equation
        val l = DoubleArray(theNumNodes) // 	to the left  of the main diagonal
        val d = DoubleArray(theNumNodes) // 	             on the main diagonal
        val r = DoubleArray(theNumNodes) // 	to the right of the main diagonal
        val c = DoubleArray(theNumNodes) // 	∂²x/∂t² or ∂²y/∂t²

        //	Let 0 label the first node
        //	and n label the last node.
        val n = theNumNodes - 1

        //	For each node except the last,
        //	compute the distance from it to the next node,
        //	which we'll use for the parameter distance Δt = tᵢ₊₁ - tᵢ.
        val theMinSplineSegmentLength: Double = 1e-8
        for (i in 0 until n) {

            Δt[i] =
                length(
                    itsNodes[firstNode + i + 1].itsNodeLocation -
                        itsNodes[firstNode + i].itsNodeLocation
                )

            Δx[i] =
                (itsNodes[firstNode + i + 1].itsNodeLocation[coordinateIndex] -
                    itsNodes[firstNode + i].itsNodeLocation[coordinateIndex])

            //	Because the user may move the control points about freely,
            //	we can't guarantee that no two adjacent points coincide.
            //	If they do, give up and draw the curve as a sequence of straight lines
            //	(which the code above has already set as the default parameterization).
            if (Δt[i] < theMinSplineSegmentLength) {
                return
            }
        }

        //	For each node we'll write an equation
        //
        //		aᵢ₀c₀ + aᵢ₁c₁ + … + aᵢₙ cᵢₙ = rhsᵢ
        //
        //	and then we'll solve the equations simultaneously.
        //	In practical terms, we get a matrix equation
        //
        //		( a₀₀  a₀₁  ⋯  a₀ₙ ) ( c₀ )   ( rhs₀ )
        //		( a₁₀  a₁₁  ⋯  a₁ₙ ) ( c₁ )   ( rhs₁ )
        //		(  ⋮    ⋮   ⋱    ⋮  ) ( ⋮  ) = (  ⋮  )
        //		( aₙ₀   aₙ₁   ⋯  aₙₙ ) ( cₙ )   ( rhsₙ )

        //	A "natural spline" has, by definition, c₀ = cₙ = 0.
        //	So the first equation may be written
        //
        //		1 c₀ + 0 c₁ + … + 0 cₙ₋₁ + 0 cₙ = 0
        //
        //	and the last may be written
        //
        //		0 c₀ + 0 c₁ + … + 0 cₙ₋₁ + 1 cₙ = 0
        //
        //	The coefficients are already consistent with "diagonal form",
        //	because these equations are already solved.
        rhs[0] = 0.0
        rhs[n] = 0.0

        //	Set up the equations for the intermediate nodes (i = 1 … n-1 ) as
        //
        //		    cᵢ   (tᵢ₊₁ - tᵢ)
        //		+ 2 cᵢ₊₁ (tᵢ₊₂ - tᵢ)
        //		+   cᵢ₊₂ (tᵢ₊₂ - tᵢ₊₁)
        //	=
        //		6 [ (xᵢ₊₂ - xᵢ₊₁) / (tᵢ₊₂ - tᵢ₊₁)
        //		  - (xᵢ₊₁ -  xᵢ ) / (tᵢ₊₁ -  tᵢ ) ]
        //
        //	for i = 1…(n-1) to solve for the remaining c's.

        for (i in 1..(n - 1)) {

            //	l[i] and r[i] refer to the off-diagonal elements in row i.
            //	That is, near the main diagonal, the matrix looks like
            //
            //		...	l[i-1]  d[i-1]  r[i-1]    0       0    ...
            //		...   0     l[ i ]  d[ i ]  r[ i ]    0    ...
            //		...   0       0     l[i+1]  d[i+1]  r[i+1] ...
            //
            l[i] = Δt[i - 1] // 	ignored in row i=1
            d[i] = 2.0 * (Δt[i - 1] + Δt[i])
            r[i] = Δt[i] // 	ignored in row i=n-1

            rhs[i] = 6.0 * (Δx[i] / Δt[i] - Δx[i - 1] / Δt[i - 1])
        }

        //	The full set of equations looks like
        //
        //		 1    0    0    0    0    0    0    0    0       0
        //		 l₁   d₁   r₁   0    0    0    0    0    0      rhs₁
        //		 0    l₂   d₂   r₂   0    0    0    0    0      rhs₂
        //		 0    0    l…   d…   r…   0    0    0    0       ⋮
        //		 0    0    0    l…   d…   r…   0    0    0       ⋮
        //		 0    0    0    0    l…   d…   r…   0    0       ⋮
        //		 0    0    0    0    0    lₙ₋₂  dₙ₋₂   rₙ₋₂  0      rhsₙ₋₂
        //		 0    0    0    0    0    0    lₙ₋₁   dₙ₋₁  rₙ₋₁ 	rhsₙ₋₁
        //		 0    0    0    0    0    0    0    0    1       0
        //
        //	Subtracting l₁ times the first row from the second,
        //	and rn₋₁ times the last from the next-to-last, gives
        //
        //		 1    0    0    0    0    0    0    0    0       0
        //		 0    d₁   r₁   0    0    0    0    0    0      rhs₁
        //		 0    l₂   d₂   r₂   0    0    0    0    0      rhs₂
        //		 0    0    l…   d…   r…   0    0    0    0       ⋮
        //		 0    0    0    l…   d…   r…   0    0    0       ⋮
        //		 0    0    0    0    l…   d…   r…   0    0       ⋮
        //		 0    0    0    0    0    lₙ₋₂  dₙ₋₂   rₙ₋₂  0      rhsₙ₋₂
        //		 0    0    0    0    0    0    lₙ₋₁   dₙ₋₁  0      rhsₙ₋₁
        //		 0    0    0    0    0    0    0    0    1       0
        //
        //	so really we need to solve only the smaller system
        //
        //		 -    -    -    -    -    -    -    -    -       -
        //		 -    d₁   r₁   0    0    0    0    0    -      rhs₁
        //		 -    l₂   d₂   r₂   0    0    0    0    -      rhs₂
        //		 -    0    l…   d…   r…   0    0    0    -       ⋮
        //		 -    0    0    l…   d…   r…   0    0    -       ⋮
        //		 -    0    0    0    l…   d…   r…   0    -       ⋮
        //		 -    0    0    0    0    lₙ₋₂  dₙ₋₂   rₙ₋₂  -      rhsₙ₋₂
        //		 -    0    0    0    0    0    lₙ₋₁   dₙ₋₁  -      rhsₙ₋₁
        //		 -    -    -    -    -    -    -    -    -       -
        //
        //	with rows and columns indexed from 1 through n-1.

        //	We've already checked that theNumNodes ≥ 3, so we know n ≥ 2,
        //	which means that the smaller system is not vacuous,
        //	that is, we've got at least one "middle equation".
        //	The code below relies on n ≥ 2 to ensure that the loop exit conditions
        //	get evaluated properly, and that we don't write where we don't intend.
        precondition(n >= 2, "Internal error: n < 2") // 	redundant error check

        //	Forward elimination
        //
        //
        //	Dividing row 1 by d₁ gives
        //
        //		d₁" = 1
        //		r₁" = r₁ / d₁
        //			= Δt₁ / (2.0 * (Δt₀ + Δt₁))
        //	so
        //		0 < r₁" < 1/2
        //
        //	The system now looks like
        //
        //		 1    r₁"  0    0    0    0    0         *
        //		 l₂   d₂   r₂   0    0    0    0         *
        //		 0    l…   d…   r…   0    0    0         *
        //		 0    0    l…   d…   r…   0    0         *
        //		 0    0    0    l…   d…   r…   0         *
        //		 0    0    0    0    lₙ₋₂  dₙ₋₂  rₙ₋₂        *
        //		 0    0    0    0    0    lₙ₋₁  dₙ₋₁        *
        //
        //	Subtracting l₂ times the first row from the second gives
        //
        //		l₂' = 0
        //		d₂' = d₂ - l₂*r₁"
        //			= 2(Δt₁ + Δt₂) - Δt₁*r₁"
        //		r₂' = r₂
        //
        //	and dividing through by d₂' gives
        //
        //		l₂" = 0
        //		d₂" = 1
        //		r₂" = Δt₂ / [ 2(Δt₁ + Δt₂) - Δt₁*r₁" ]
        //
        //	Because we already knew that 0 < r₁" < 1/2,
        //	it follows that 0 < r₂" < 1/2 as well.
        //
        //	The system now looks like
        //
        //		 1    r₁"  0    0    0    0    0         *
        //		 0    1    r₂"  0    0    0    0         *
        //		 0    l₃   d₃   r₃   0    0    0         *
        //		 0    0    l…   d…   r…   0    0         *
        //		 0    0    0    l…   d…   r…   0         *
        //		 0    0    0    0    lₙ₋₂  dₙ₋₂   rₙ₋₂       *
        //		 0    0    0    0    0    lₙ₋₁   dₙ₋₁       *
        //
        //	Moving on to row 3 gives
        //
        //		l₃' = 0
        //		d₃' = d₃ - l₃*r₂"
        //			= 2(Δt₂ + Δt₃) - Δt₂*r₂"
        //		r₃' = r₃
        //			= Δt₃
        //
        //	and then
        //
        //		l₃' = 0
        //		d₃' = 1
        //		r₃' = Δt₃ / [ 2(Δt₂ + Δt₃) - Δt₂*r₂" ]
        //
        //	Because we already knew that 0 < r₂" < 1/2,
        //	it follows that 0 < r₃" < 1/2 as well.
        //
        //	Proposition.  0 < rᵢ" < 1/2 for all i.
        //	Proof.  By induction, as above.
        //
        //	Corollary.  If Δtᵢ > 0 for all i, then dᵢ > 0 for all i.
        //	Proof.
        //		dᵢ₊₁' = dᵢ₊₁ - lᵢ₊₁*rᵢ"
        //			  = 2(Δtᵢ + Δtᵢ₊₁) - Δtᵢ*rᵢ"
        //			  = (2 - rᵢ")*Δtᵢ + 2*Δtᵢ₊₁
        //			  >  2*Δtᵢ₊₁
        //			  > 0
        //
        //	The corollary guarantees that we will never encounter a zero
        //	on the main diagonal.  We can safely divide through by dᵢ₊₁'.
        //	There is never any need to pivot.

        //	Handle rows 1 through n-2 normally.
        //	(We'll deal with row n-1 momentarily.)
        if (n >= 3) {
            for (i in 1..(n - 2)) {

                //	Divide row i by d.
                r[i] /= d[i]
                rhs[i] /= d[i]
                //	d[i]   = 1.0	No need to actually write d=1.

                //	Subtract l[i+1] times row i from row i+1.
                //	l[i+1]   = 0.0		No need to actually write l=0.
                d[i + 1] -= l[i + 1] * r[i]
                rhs[i + 1] -= l[i + 1] * rhs[i]
            }
        }

        //	Divide row n-1 by d, but don't try to subtract it from anything.
        rhs[n - 1] /= d[n - 1]
        //	d[n-1]   = 1.0	No need to actually write d=1.

        //	Back substitution
        if (n >= 3) {

            for (i in (2..(n - 1)).reversed()) {

                //	Subtract r[i-1] times row i from row i-1.
                rhs[i - 1] -= r[i - 1] * rhs[i]
                //	r[i-1]		= 0.0		No need to actually write r=0.
            }
        }

        //	The solution now sits in rhs[].
        //	We solved the equations in linear time.  :-)
        for (i in 0..n) {

            c[i] = rhs[i] // 	copy for conceptual clarity only
        }

        for (i in 0..(n - 1)) {

            //	For simplicity we may re-parameterize each arc
            //	running from one node to the next one
            //	in terms of a parameter u running from 0 to 1, given by
            //
            //		    ( t   - tᵢ)
            //		u = -----------
            //		    (tᵢ₊₁ - tᵢ)
            //
            //	For each such arc, the spline then takes the form
            //
            //		Sᵢ(u) = ξ₀(1-u) + ξ₁u + ξ₂(1-u)³ + ξ₃u³
            //
            //	where
            //
            //		ξ₀ =  xᵢ  -   cᵢ(tᵢ₊₁ - tᵢ)²/6
            //		ξ₁ = xᵢ₊₁ - cᵢ₊₁(tᵢ₊₁ - tᵢ)²/6
            //		ξ₂ =  cᵢ (tᵢ₊₁ - tᵢ)²/6
            //		ξ₃ = cᵢ₊₁(tᵢ₊₁ - tᵢ)²/6
            //
            //	Note:  In principle x, c and ξ are are 2-element vectors,
            //	here we're computing just one component c and ξ
            //	(namely the component corresponding to the coordinateIndex).

            val theFactor = Δt[i] * Δt[i] * (1.0 / 6.0)

            itsNodes[firstNode + i].ξ[0, coordinateIndex] =
                (itsNodes[firstNode + i].itsNodeLocation[coordinateIndex] - c[i] * theFactor)

            itsNodes[firstNode + i].ξ[1, coordinateIndex] =
                (itsNodes[firstNode + i + 1].itsNodeLocation[coordinateIndex] -
                    c[i + 1] * theFactor)

            itsNodes[firstNode + i].ξ[2, coordinateIndex] = c[i] * theFactor

            itsNodes[firstNode + i].ξ[3, coordinateIndex] = c[i + 1] * theFactor
        }
    }

    // MARK: -
    // MARK: Split node

    fun splitNode(nodeToSplit: SplineNode): Pair<SplineNode, SplineNode> { // 	returns two new nodes

        val i = itsNodes.indexOfFirst { node -> node === nodeToSplit }
        if (i < 0) {

            assertionFailure(
                "Internal error:  splitNode received a SplineNode that's not part of this CubicSpline"
            )

            return Pair(
                SplineNode(location = Double2(0.25, 0.0), type = SplineNodeType.smooth),
                SplineNode(location = Double2(0.75, 0.0), type = SplineNodeType.smooth),
            )
        }

        val theNodeType = nodeToSplit.itsNodeType

        val aNewNodeA: SplineNode
        val aNewNodeB: SplineNode

        //	Choose aNewNodeA
        if (i == 0) {

            //	nodeToSplit is the first node in the curve,
            //	and therefore has no preceding node.
            //	Place aNewNodeA at the same location as nodeToSplit itself.

            aNewNodeA =
                SplineNode(
                    location = nodeToSplit.itsNodeLocation,
                    type = SplineNodeType.corner,
                )
        } else {

            //	nodeToSplit is not the first node in the curve.

            val theNodeBefore = itsNodes[i - 1]

            //	Let aNewNodeA lie part way along the spline
            //	from theNodeBefore to nodeToSplit.

            val u = 2.0 / 3.0
            val uu = 1.0 - u
            val ξ = theNodeBefore.ξ

            val theLocationA = (uu * ξ[0] + u * ξ[1] + uu * uu * uu * ξ[2] + u * u * u * ξ[3])

            aNewNodeA =
                SplineNode(
                    location = theLocationA,
                    type = theNodeType,
                )
        }

        //	Choose aNewNodeB
        if (i == itsNodes.size - 1) {

            //	nodeToSplit is the last node in the curve,
            //	and therefore has no following node.
            //	Place aNewNodeB at the same location as nodeToSplit itself.

            aNewNodeB =
                SplineNode(
                    location = nodeToSplit.itsNodeLocation,
                    type = SplineNodeType.corner,
                )
        } else {

            //	nodeToSplit is not the last node in the curve.

            //	Let aNewNodeB lie part way along the spline
            //	from nodeToSplit to the node that follows it.

            val u = 1.0 / 3.0
            val uu = 1.0 - u
            val ξ = nodeToSplit.ξ

            val theLocationB = (uu * ξ[0] + u * ξ[1] + uu * uu * uu * ξ[2] + u * u * u * ξ[3])

            aNewNodeB =
                SplineNode(
                    location = theLocationB,
                    type = theNodeType,
                )
        }

        return Pair(aNewNodeA, aNewNodeB)
    }
}

//	If a node lies in the interior of a curve,
//	should it be drawn as a smooth node or a corner node?
//
//		Note:  A curve's endpoints are always drawn as "corner points",
//		with the cubic spline's second derivatives zero there.
//		In particular a curve's endpoints ignore their SplineNodeType.
//		An endpoint's SplineNodeType will become relevant only if
//		an Undo operation adds back another node, making
//		the endpoint node become an interior node again.
//
enum class SplineNodeType(val rawValue: String) {

    smooth("smooth"),
    corner("corner");

    val id: String
        get() = this.rawValue

    //	Port note:  returns the key itself ("Smooth" or "Corner"),
    //	where the original wraps it in a SwiftUI LocalizedStringKey.
    fun localizedNameKey(): String {
        return this.rawValue.replaceFirstChar { it.uppercase() }
    }

    companion object {

        //	Swift's SplineNodeType(rawValue:)
        fun fromRawValue(rawValue: String): SplineNodeType? = entries.firstOrNull {
            it.rawValue == rawValue
        }
    }
}

//	We implement SplineNode as a class (not a struct) so that
//	we can keep a reliable reference to a selected SplineNode.
//	In particular, when the user changes, say, the selected nodes's
//	location, that will change the location of the instance
//	in CubicSpline.itsNodes as well (not just the location of a copy,
//	as would be the case with a struct).
//
class SplineNode(
    location: Double2,
    type: SplineNodeType,
) {

    //	Location in [0,1] unit cell coordinates.
    var itsNodeLocation: Double2 = location

    var itsNodeType: SplineNodeType = type

    //	If this SplineNode isn't the last SplineNode in its CubicSpline,
    //	then we may parameterize the spline running from this SplineNode
    //	to the next one as
    //
    //		S(u) = ξ₀(1-u) + ξ₁u + ξ₂(1-u)³ + ξ₃u³
    //
    //	where the ξ are constants and u runs from 0 to 1.
    //
    //		Note:  The parameterization ξ doesn't get stored to disk,
    //		but gets recomputed when a drawing gets loaded.
    //		Maintaining a curve as a set of node positions only
    //		(without the parameterization) simplifies the file format
    //		as well as the Editor's logic. In any case,
    //		computeCubicSpline() provides a fast O(n) algorithm,
    //		and it gets called rarely.
    //
    //
    //	refreshParameterization() will compute
    //	the parameterization coefficients ξ.
    //	For now we just set a placeholder value.
    //
    var ξ: Double4x2 = Double4x2()
}
