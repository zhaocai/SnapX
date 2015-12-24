class Snapper
{
	__New(settings)
	{
		this.settings := settings
		
		this.TrackedWindows := []
		this.LastOperation := Operation.None
		this.LastWindowHandle := -1
		this.StillHoldingWinKey := 0
		
		onExitMethod := ObjBindMethod(this, "exitFunc")
		OnExit(onExitMethod)
	}
	
	moveWindow(horizontalDirection, horizontalSize, verticalDirection, verticalSize)
	{
		; state: minimized and LWin not released yet
		if (this.LastOperation == Operation.Minimized && this.StillHoldingWinKey)
		{
debug.write("state: minimized")
			; action: increase width
			if (horizontalSize > 0)
			{
debug.write("   action: restore")
				this.StillHoldingWinKey := 0
				this.LastOperation := Operation.Restored
				WinRestore, % "ahk_id " this.LastWindowHandle  ; WinRestore followed by WinActivate, with ahk_id specified explicitely on each, was the only way I could get
				WinActivate, % "ahk_id " this.LastWindowHandle ; Win+Down, Win+Up (particularly when done in quick succession) to restore and set focus again reliably.
			}
			; action: anything else
			return
		}
		
		WinGet, activeWindowHandle, ID, A
		
		WinGet, activeWindowStyle, Style, A
		
		; state: not resizable
		if (!(activeWindowStyle & WS.SIZEBOX)) ; if window is not resizable
		{
			; state: minimizable
			if (activeWindowStyle & WS.MINIMIZEBOX) ; if window is minimizable
			{
				; action: decrease width
				if (horizontalSize < 0)
				{
debug.write("state: restored")
debug.write("   action: minimize")
					this.LastWindowHandle := activeWindowHandle
					this.minimizeAndKeyWaitLWin()
				}
				; action: anything else
				; (continue)
			}
			return
		}

		index := IndexOf(this.TrackedWindows, activeWindowHandle, "handle")
		if index < 1
		{
			window := new SnapWindow(activeWindowHandle)
			index := this.TrackedWindows.Push(window)
		}
		
		window := this.TrackedWindows[index]
		this.LastWindowHandle := window.handle
		
		monitorId := GetMonitorId(window.handle)
		mon := new SnapMonitor(monitorId)
		
		WinGet, minMaxState, MinMax, A
		widthFactor  := mon.workarea.w / this.settings.horizontalSections
		heightFactor := mon.workarea.h / this.settings.verticalSections
		
		; state: minimized
		if (minMaxState < 0)
		{
debug.write("state: minimized")
			; action: increase width
			if (horizontalSize > 0)
			{
debug.write("   action: restore")
				this.LastOperation := Operation.Restored
				WinRestore, A
			}
			; action: anything else
			return
		}
		
		; state: maximized
		else if (minMaxState > 0)
		{
debug.write("state: maximized")
			; action: decrease width
			if (horizontalSize < 0)
			{
debug.write("   action: restore snapped")
				this.LastOperation := Operation.RestoredSnapped
				WinRestore, A
			}
			; action: anything else
			return
		}
		
		; state: snapped
		else if (window.snapped == 1)
		{
debug.write("state: snapped")
			; state: width == max - 1 && height == max
			;    or: width == max     && height == anything
			if (window.grid.width == this.settings.horizontalSections - 1 && window.grid.height == this.settings.verticalSections
				|| window.grid.width == this.settings.horizontalSections)
			{
				; action: increase width
				; or state: top edge touching monitor edge and height == max - 1
				;   action: decrease height
				; or state: bottom edge touching monitor edge and height == max - 1
				;   action: increase height
				if (horizontalSize > 0
					|| (window.grid.top == 0 && window.grid.height == this.settings.verticalSections - 1 && verticalSize < 0)
					|| (window.grid.top == 1 && window.grid.height == this.settings.verticalSections - 1 && verticalSize > 0))
				{
debug.write("   action: maximize")
					this.LastOperation := Operation.Maximized
					WinMaximize, A
					return
				}
				; action: anything else
				; (continue)
			}
			
			; state: width == 1
			if (window.grid.width == 1)
			{
				; action: decrease width
				if (horizontalSize < 0)
				{
debug.write("   action: restore unsnapped")
					window.snapped := 0
					WinMove, A, , window.restoredpos.left   * mon.workarea.w + mon.workarea.x
									, window.restoredpos.top    * mon.workarea.h + mon.workarea.y
									, window.restoredpos.width  * mon.workarea.w
									, window.restoredpos.height * mon.workarea.h ; "restore" from snapped state
					return
				}
				; action: anything else
				; (continue)
			}
			
			; state: height == 1
			if (window.grid.height == 1)
			{
				;    state: top edge touching monitor edge
				;   action: increase height
				; or state: bottom edge touching monitor edge
				;   action: decrease height
				if ((window.grid.top == 0 && verticalSize > 0) || (window.grid.top == this.settings.verticalSections - 1 && verticalSize < 0))
				{
					; (do nothing)
					return
				}
			}
			
			; action: all
debug.write("   action: " (horizontalDirection ? "move horizontal" : horizontalSize ? "resize horizontal" : verticalDirection ? "move vertical" : verticalSize ? "resize vertical" : "what?"))
			this.LastOperation := Operation.Moved
			window.grid.left := window.grid.left + horizontalDirection
			window.grid.left := window.grid.left + (horizontalSize < 0 && window.grid.left != 0 && window.grid.left + window.grid.width >= this.settings.horizontalSections ? 1 : 0) ; keep right edge attached to monitor edge if shrinking
			window.grid.width := window.grid.width + horizontalSize
			window.grid.top := window.grid.top + verticalDirection
		}
		
		; state: restored
		else if (window.snapped == 0)
		{
debug.write("state: restored")
			; action: decrease width
			if (horizontalSize < 0)
			{
				; state: minimizable
				if (activeWindowStyle & WS.MINIMIZEBOX) ; if window is minimizable
				{
debug.write("   action: minimize")
					this.minimizeAndKeyWaitLWin()
				}
				return
			}
			
			window.UpdatePosition()
			
			; action: anything else
debug.write("   action: snap")
			this.LastOperation := Operation.Snapped
			window.snapped := 1
; Snap based on left/right edges and left/right direction pushed
			window.grid.left := Floor(((horizontalDirection < 0 ? window.position.x : horizontalDirection > 0 ? window.position.r : window.position.cx) - mon.workarea.x) / mon.workarea.w * this.settings.horizontalSections)
; Original - Snap based on center coordinates
;			window.grid.left := Floor((window.position.cx - mon.workarea.x) / mon.workarea.w * this.settings.horizontalSections)
; Always snaps to current centercoords position, regardless of snap direction pushed
;			(do nothing more)
; Does not snap to current centercoords position - always left or right of current centercoords (unless against edge, of course)
;			window.grid.left := window.grid.left + horizontalDirection
; Shift one more snap direction if starting snap position is on opposite side of the screen from indicated direction
;			window.grid.left := window.grid.left
;										+ ((this.settings.horizontalSections - 1) / 2 - window.grid.left > 0 == horizontalDirection > 0 ; if snap position is on the opposite side of the screen as horizontal direction pushed (snap is 0 or 1 and win+right pushed; or snap is 2 or 3 and win+left pushed)
;											|| (this.settings.horizontalSections - 1) / 2 - window.grid.left == 0 ; or if snap position is exact center (forward-compatibility for allowing horizontalSections == 3 (or any odd number))
;											 ? horizontalDirection ; shift one more snap indicated direction
;											 : 0)
; Always snap against edge in direction pushed
;			window.grid.left := horizontalDirection < 0 ? 0 : horizontalDirection > 0 ? this.settings.horizontalSections - 1 : window.grid.left
; Always snap against center edge in direction pushed
;			window.grid.left := horizontalDirection < 0 ? this.settings.horizontalSections // 2 - 1 : horizontalDirection > 0 ? (this.settings.horizontalSections + 1) // 2 : window.grid.left
			window.grid.width := 1 + horizontalSize
			window.grid.top := 0
			window.grid.height := this.settings.verticalSections
			window.restoredpos.left   := (window.position.x - mon.workarea.x) / mon.workarea.w
			window.restoredpos.top    := (window.position.y - mon.workarea.y) / mon.workarea.h
			window.restoredpos.width  :=  window.position.w                   / mon.workarea.w
			window.restoredpos.height :=  window.position.h                   / mon.workarea.h
		}
		
		; Handle vertical snap
		if (verticalSize)
		{
			; state: full vertical height
			if (window.grid.top == 0 && window.grid.height == this.settings.verticalSections)
			{
				if (verticalSize < 0)
				{
					window.grid.top := window.grid.top + 1
				}
				window.grid.height := window.grid.height - 1
			}
			; state: top edge touching monitor edge
			else if (window.grid.top == 0)
			{
				window.grid.height := window.grid.height - verticalSize
			}
			; state: bottom edge touching monitor edge
			else if (window.grid.top + window.grid.height == this.settings.verticalSections)
			{
				window.grid.top := window.grid.top - verticalSize
				window.grid.height := window.grid.height + verticalSize
			}
			; state: not touching top or bottom
			else
			{
				if (verticalSize > 0)
				{
					window.grid.top := window.grid.top - verticalSize
					window.grid.height := window.grid.height + verticalSize
				}
				else if (verticalSize < 0)
				{
					window.grid.height := window.grid.height - verticalSize
				}
			}
		}
		
		; Enforce snap boundaries
		
		if (window.grid.left + window.grid.width > this.settings.horizontalSections)
		{
			window.grid.left := window.grid.left - 1
		}
		
		if (window.grid.left < 0)
		{
			window.grid.left := 0
		}
		
		if (window.grid.top + window.grid.height > this.settings.verticalSections)
		{
			window.grid.top := window.grid.top - 1
		}
		
		if (window.grid.top < 0)
		{
			window.grid.top := 0
		}
		
		; Move/resize snap
		WinMove, A, , window.grid.left   * widthFactor  +    window.position.xo + mon.workarea.x
						, window.grid.top    * heightFactor                         + mon.workarea.y
						, window.grid.width  * widthFactor  + -2*window.position.xo
						, window.grid.height * heightFactor + -1*window.position.xo ; + -2*window.position.yo + 1
	}

	minimizeAndKeyWaitLWin()
	{
		this.StillHoldingWinKey := 1
		this.LastOperation := Operation.Minimized
		WinMinimize, A
		While this.StillHoldingWinKey
		{
			KeyWait, LWin, T0.25
			if (!ErrorLevel)
			{
				this.StillHoldingWinKey := 0
			}
		}
	}

	exitFunc(exitReason, exitCode)
	{
		TrayTip, % this.settings.programTitle, Resetting snapped windows to their pre-snap size and position
		
		for i, window in this.TrackedWindows
		{
			; state: snapped
			if (window.snapped == 1)
			{
				monitorId := GetMonitorId(window.handle)
				mon := new SnapMonitor(monitorId)
				
				WinGet, minMaxState, MinMax, % "ahk_id " window.handle
				
				; state: minimized or maximized
				if (minMaxState != 0)
				{
					GetWindowPlacement(window.handle, wp)
					wp.rcNormalPosition.left   :=                            window.restoredpos.left   * mon.workarea.w + mon.area.x
					wp.rcNormalPosition.top    :=                            window.restoredpos.top    * mon.workarea.h + mon.area.y
					wp.rcNormalPosition.right  := wp.rcNormalPosition.left + window.restoredpos.width  * mon.workarea.w
					wp.rcNormalPosition.bottom := wp.rcNormalPosition.top  + window.restoredpos.height * mon.workarea.h
					SetWindowPlacement(window.handle, wp) ; set restored position to pre-snap state (maintains current minimized or maximized status)
				}
				else
				{
					WinMove, % "ahk_id " window.handle, , window.restoredpos.left   * mon.workarea.w + mon.workarea.x
																	, window.restoredpos.top    * mon.workarea.h + mon.workarea.y
																	, window.restoredpos.width  * mon.workarea.w
																	, window.restoredpos.height * mon.workarea.h ; "restore" from snapped state
				}
			}
		}
	}
}