// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

package com.cinderblocksoftware.kaleidopaint.geometry

//	Stands in for Foundation's UndoManager, as KaleidoPaint uses it.
//
//	KaleidoPaintDocument.doSomethingUndoably() performs an operation and
//	registers a closure that will undo it.  When the user asks for an undo,
//	the manager calls that closure;  the closure registers its own inverse,
//	which the manager, because an undo is under way, files as a redo.
//	Doing something new forgets whatever could have been redone.
//
//	Foundation gathers everything registered during one pass of the run loop
//	into a single undo step.  KaleidoPaint registers exactly one closure
//	per user action, so here each registration is its own step.

class UndoManager {

    private val itsUndoStack = ArrayDeque<() -> Unit>()
    private val itsRedoStack = ArrayDeque<() -> Unit>()

    private var itsUndoIsInProgress = false
    private var itsRedoIsInProgress = false

    val canUndo: Boolean
        get() = itsUndoStack.isNotEmpty()

    val canRedo: Boolean
        get() = itsRedoStack.isNotEmpty()

    fun registerUndo(handler: () -> Unit) {

        if (itsUndoIsInProgress) {

            //	The inverse of an undo is a redo.
            itsRedoStack.addLast(handler)
        } else {

            itsUndoStack.addLast(handler)

            //	A new action (as opposed to a redo re-registering its undo)
            //	makes the old redos meaningless.
            if (!itsRedoIsInProgress) {
                itsRedoStack.clear()
            }
        }
    }

    fun undo() {

        val theHandler = itsUndoStack.removeLastOrNull() ?: return

        itsUndoIsInProgress = true
        try {
            theHandler()
        } finally {
            itsUndoIsInProgress = false
        }
    }

    fun redo() {

        val theHandler = itsRedoStack.removeLastOrNull() ?: return

        itsRedoIsInProgress = true
        try {
            theHandler()
        } finally {
            itsRedoIsInProgress = false
        }
    }

    fun removeAllActions() {
        itsUndoStack.clear()
        itsRedoStack.clear()
    }
}
