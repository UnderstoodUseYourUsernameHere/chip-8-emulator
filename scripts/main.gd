extends Control

@onready var rom_picker: OptionButton = $%RomPicker
@onready var screen: TextureRect = $%Screen
@onready var debug_label: Label = $%DebugLabel
@onready var disassembly_label: Label = $%DisassemblyLabel
@onready var breakpoint_edit: LineEdit = $%BreakpointEdit
@onready var help_overlay: PanelContainer = $%HelpOverlay
@onready var memory_label: Label = $%MemoryLabel
@onready var controls_label: Label = $%ControlsLabel
@onready var speed_slider: HSlider = $%SpeedSlider
@onready var wait_check: CheckBox = $%WaitCheck
@onready var keypad_grid: GridContainer = $%KeypadGrid
@onready var profile_picker: OptionButton = $%ProfilePicker
@onready var quirk_box: VBoxContainer = $%QuirkBox
@onready var trace_label: Label = $%TraceLabel

const FONT_START := 0x50
const FONT := [
	0xF0, 0x90, 0x90, 0x90, 0xF0, ## 0
	0x20, 0x60, 0x20, 0x20, 0x70, ## 1
	0xF0, 0x10, 0xF0, 0x80, 0xF0, ## 2
	0xF0, 0x10, 0xF0, 0x10, 0xF0, ## 3
	0x90, 0x90, 0xF0, 0x10, 0x10, ## 4
	0xF0, 0x80, 0xF0, 0x10, 0xF0, ## 5
	0xF0, 0x80, 0xF0, 0x90, 0xF0, ## 6
	0xF0, 0x10, 0x20, 0x40, 0x40, ## 7
	0xF0, 0x90, 0xF0, 0x90, 0xF0, ## 8
	0xF0, 0x90, 0xF0, 0x10, 0xF0, ## 9
	0xF0, 0x90, 0xF0, 0x90, 0x90, ## A
	0xE0, 0x90, 0xE0, 0x90, 0xE0, ## B
	0xF0, 0x80, 0x80, 0x80, 0xF0, ## C
	0xE0, 0x90, 0x90, 0x90, 0xE0, ## D
	0xF0, 0x80, 0xF0, 0x80, 0xF0, ## E
	0xF0, 0x80, 0xF0, 0x80, 0x80, ## F
]

const KEYMAP := [
	KEY_X, KEY_1, KEY_2, KEY_3, ## 0 1 2 3
	KEY_Q, KEY_W, KEY_E, KEY_A, ## 4 5 6 7 
	KEY_S, KEY_D, KEY_Z, KEY_C, ## 8 9 A B
	KEY_4, KEY_R, KEY_F, KEY_V, ## C D E F
]
var keys := PackedByteArray()
var waiting_for_key := -1
var keys_used := {}
var announced_any_key := false

const KEYPAD_ORDER := [
	0x1, 0x2, 0x3, 0xC,
	0x4, 0x5, 0x6, 0xD,
	0x7, 0x8, 0x9, 0xE,
	0xA, 0x0, 0xB, 0xF
]
var pad_keys := PackedByteArray()
var pad_buttons := {}

const ROM_FOLDERS := ["res://roms", "res://games"]
var rom_names: Array[String] = []
var rom_paths := {}

const REWIND_MAX_TICKS := 600

var rewind_history: Array[Dictionary] = []
var rewinding := false

var rng := RandomNumberGenerator.new()

const QUIRK_ORDER := [
	"vf_reset",
	"shift_vy",
	"memory_increment",
	"jump_v0",
	"clip",
]

const QUIRK_LABELS := {
	"vf_reset": "Logic operations clear VF",
	"shift_vy": "Shift instructions read VY",
	"memory_increment": "FX55 / FX65 advance I",
	"jump_v0": "BNNN offset uses V0",
	"clip": "Sprites clip at screen edges",
}

const QUIRK_TOOLTIPS := {
	"vf_reset":
		"8XY1, 8XY2 and 8XY3 set VF to zero on the original CHIP-8.",
	
	"shift_vy":
		"On the original CHIP-8, 8XY6 and 8XYE shift VY and store the result in VX. Later interpreters shift VX itself.",
	
	"memory_increment":
		"On the original CHIP-8, FX55 and FX65 move I forward after transferring registers.",
	
	"jump_v0":
		"Original behavior: BNNN jumps to NNN + V0. Later interpreters use the register named by X.",
	
	"clip":
		"When enabled, sprite pixels beyond the right or bottom edge are discarded. When disabled they wrap around the screen instead.",
}

var quirks := {
	"vf_reset": true,
	"shift_vy": true,
	"memory_increment": true,
	"jump_v0": true,
	"clip": true,
}

var quirk_checks := {}

const PROFILE_ORDER := [
	"Original CHIP-8",
	"Modern quirks",
	"Custom",
]

const COMPATIBILITY_PROFILES := {
	"Original CHIP-8": {
		"vf_reset": true,
		"shift_vy": true,
		"memory_increment": true,
		"jump_v0": true,
		"clip": true,
		"display_wait": true,
	},
	
	"Modern quirks": {
		"vf_reset": false,
		"shift_vy": false,
		"memory_increment": false,
		"jump_v0": false,
		"clip": true,
		"display_wait": false,
	}
}

var instructions_per_frame := 11
var current_rom := ""
var paused := false
var paused_before_help := false
var last_opcode := 0 ## These ones are something im not sure of, hopefully they work as i think they will
var last_pc := 0
var status := ""
var faulted := false
var frame_blocked := false

var trace: Array[int] = []
const TRACE_MAX := 32

var breakpoints := {}
var skip_breakpoint_pc := -1 
var stopped_breakpoint_pc := -1

var stack: Array[int] = []
var delay_timer := 0
var sound_timer := 0
var rom_loaded := false

var img: Image
var tex: ImageTexture

var display := PackedByteArray()
var display_wait_enabled := true
var drew_this_frame := false

var open_dialog := FileDialog.new()

var beep := AudioStreamPlayer.new()

var memory := PackedByteArray()
var V := PackedByteArray()  ## Registers from VO to VF
var I := 0 ## This is the index register
var pc := 0x200 ## pc stands for program counter, if you arent in the know. 

var mem_mode := 0
var mem_base := 0x200
const MEM_ROWS := 8
const MEM_COLS := 16

func update_memory_view() -> void:
	if not rom_loaded:
		memory_label.text = "NO MEMORY"
		return
	
	var target := -1
	if mem_mode == 0: target = pc
	elif mem_mode == 1: target = I
	if target >= 0:
		mem_base = (target - target % MEM_COLS) - 3 * MEM_COLS
	mem_base = clampi(mem_base, 0, memory.size() - MEM_ROWS * MEM_COLS)
	
	var modes := ["FOLLOW PC", "FOLLOW I", "MANUAL"]
	var t := "MEMORY [%s] H=mode [ ]=page\n\n" % modes[mem_mode]
	for r in MEM_ROWS:
		var row := mem_base + r * MEM_COLS
		t += "%03X:" % row
		for c in MEM_COLS:
			var a := row + c
			var mark := " "
			if a == pc or a == pc + 1: mark = ">"
			elif a == I: mark = "*"
			t += "%s%02X" % [mark, memory[a]]
		t += "\n"
	memory_label.text = t

func update_trace_view() -> void:
	if not rom_loaded:
		trace_label.text = "NO TRACE"
		return
	
	var text := "RECENT INSTRUCTIONS\n\n"
	var start := maxi(0, trace.size() - 20)
	
	for index in range(start, trace.size()):
		var packed_entry: int = trace[index]
		var trace_pc := packed_entry >> 16
		var trace_opcode := packed_entry & 0xFFFF
		
		text += "%03X %04X %s\n" % [
			trace_pc,
			trace_opcode,
			disassemble(trace_opcode)
		]
	trace_label.text = text

func load_rom(path: String) -> bool:
	memory.resize(4096) ## Resets everything to a clean slate
	memory.fill(0)
	status = ""
	V.resize(16)
	V.fill(0)
	display.resize(64 * 32)
	display.fill(0)
	stack.clear()
	rewind_history.clear()
	rewinding = false
	trace.clear()
	rng.randomize()
	keys.resize(16) 
	keys.fill(0)
	pad_keys.fill(0)
	keys_used.clear()
	announced_any_key = false
	faulted = false
	frame_blocked = false
	skip_breakpoint_pc = -1
	stopped_breakpoint_pc = -1
	last_pc = -1
	last_opcode = -1
	waiting_for_key = -1
	I = 0
	pc = 0x200
	delay_timer = 0
	sound_timer = 0
	
	for i in FONT.size():  ## Font gets loaded into the reserved area
		memory[FONT_START + i] = FONT[i]
	
	var rom := FileAccess.get_file_as_bytes(path)
	
	if rom.is_empty():
		push_error("Could not load ROM: " + path)
		return false
	
	if rom.size() > memory.size() - 0x200:
		push_error("ROM is too large to fit in CHIP-8 memory: " + path)
		return false
	
	for i in rom.size():
		memory[0x200 + i] = rom[i]
	
	print("Loaded ", rom.size(), " bytes from ", path)
	return true

func reset_rom() -> void:
	rom_loaded = load_rom(current_rom)

func scan_roms() -> void:
	rom_names.clear()
	rom_paths.clear()
	for folder in ROM_FOLDERS:
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for f in DirAccess.get_files_at(folder):
			if f.get_extension().to_lower() != "ch8":
				continue
			var pretty := f.get_basename().replace("-", " ").replace("_", " ")
			rom_names.append(pretty)
			rom_paths[pretty] = folder + "/" + f
	rom_names.sort()

func setup_screen() -> void:
	img = Image.create_empty(64, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	tex = ImageTexture.create_from_image(img)
	screen.texture = tex
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func setup_toolbar() -> void:
	%PauseButton.pressed.connect(toggle_pause)
	%ResetButton.pressed.connect(reset_rom)
	for b in [%PauseButton, %ResetButton, %OpenButton, %HelpButton]:
		b.focus_mode = Control.FOCUS_NONE

func setup_compatibility_settings() -> void:
	profile_picker.clear()
	
	for profile_name in PROFILE_ORDER:
		profile_picker.add_item(profile_name)
	
	profile_picker.focus_mode = Control.FOCUS_NONE
	profile_picker.item_selected.connect(_on_profile_selected)
	
	for quirk_name in QUIRK_ORDER:
		var checkbox := CheckBox.new()
		
		checkbox.text = str(QUIRK_LABELS[quirk_name])
		checkbox.tooltip_text = str(QUIRK_TOOLTIPS[quirk_name])
		checkbox.focus_mode = Control.FOCUS_NONE
		
		checkbox.toggled.connect(
			_on_quirk_toggled.bind(quirk_name)
		)
		
		quirk_box.add_child(checkbox)
		quirk_checks[quirk_name] = checkbox
	
	apply_compatibility_profile("Original CHIP-8")

func apply_compatibility_profile(profile_name: String) -> void:
	if not COMPATIBILITY_PROFILES.has(profile_name):
		return
	
	var profile: Dictionary = COMPATIBILITY_PROFILES[profile_name]
	
	for quirk_name in QUIRK_ORDER:
		quirks[quirk_name] = bool(profile[quirk_name])
		
	display_wait_enabled = bool(profile["display_wait"])
	
	sync_compatibility_controls()
	rewind_history.clear()
	
	status = "Compat. profile: " + profile_name

func sync_compatibility_controls() -> void:
	for quirk_name in QUIRK_ORDER:
		var checkbox: CheckBox = quirk_checks[quirk_name]
		
		checkbox.set_pressed_no_signal(
			bool(quirks[quirk_name])
		)
	wait_check.set_pressed_no_signal(display_wait_enabled)

func _on_profile_selected(index: int) -> void:
	if index < 0 or index >= PROFILE_ORDER.size():
		return
	
	var profile_name: String = PROFILE_ORDER[index]
	
	if profile_name == "Custom":
		return
	
	apply_compatibility_profile(profile_name)

func mark_profile_custom() -> void:
	var custom_index := PROFILE_ORDER.find("Custom")
	
	if custom_index >= 0:
		profile_picker.select(custom_index)

func _on_quirk_toggled(
	enabled: bool,
	quirk_name: String
) -> void:
	quirks[quirk_name] = enabled
	
	mark_profile_custom()
	rewind_history.clear()
	
	status = "Custom Compatibility settings enabled."

func setup_keypad() -> void:
	pad_keys.resize(16)
	pad_keys.fill(0)
	
	for key in KEYPAD_ORDER:
		var button := Button.new()
		
		button.text = "%X\n%s" % [
			key, 
			OS.get_keycode_string(KEYMAP[key])
		]
		button.custom_minimum_size = Vector2(64, 44)
		button.focus_mode = Control.FOCUS_NONE
		
		button.button_down.connect(
			_on_keypad_changed.bind(key, true)
		)
		
		button.button_up.connect(
			_on_keypad_changed.bind(key, false)
		)
		
		keypad_grid.add_child(button)
		pad_buttons[key] = button

func _on_keypad_changed(key: int, down: bool) -> void:
	pad_keys[key] = 1 if down else 0

func refresh_keypad() -> void:
	for key in KEYPAD_ORDER:
		var button: Button = pad_buttons[key]
		
		if keys.size() == 16 and keys[key] == 1:
			button.modulate = Color("#8fffa0")
		elif keys_used.has(key):
			button.modulate = Color("#ffd27f")
		else:
			button.modulate = Color.WHITE

func setup_settings() -> void:
	speed_slider.value = instructions_per_frame
	speed_slider.value_changed.connect(
		func(v): instructions_per_frame = int(v)
	)
	
	wait_check.button_pressed = display_wait_enabled
	wait_check.toggled.connect(_on_display_wait_toggled)
	
	speed_slider.focus_mode = Control.FOCUS_NONE
	wait_check.focus_mode = Control.FOCUS_NONE

func setup_sound() -> void:
	var rate := 22050
	var frames := int(rate / 440.0)
	var data := PackedByteArray()
	data.resize(frames)
	for i in frames:
		data[i] = 64 if i < frames / 2 else 192
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0 
	stream.loop_end = frames
	beep.stream = stream
	beep.volume_db = -12
	add_child(beep)

func setup_picker() -> void:
	scan_roms()
	rom_picker.clear()
	rom_picker.fit_to_longest_item = false
	rom_picker.clip_text = true
	rom_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for rom_name in rom_names:
		rom_picker.add_item(rom_name)
		rom_picker.set_item_tooltip(rom_picker.item_count - 1, rom_name)
	rom_picker.item_selected.connect(_on_rom_selected)
	rom_picker.focus_mode = Control.FOCUS_NONE

func setup_open_dialog() -> void:
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_dialog.filters = PackedStringArray(["*.ch8 ; CHIP-8 ROM"])
	open_dialog.title = "Open CHIP-8 ROM"
	open_dialog.file_selected.connect(load_external_rom)
	add_child(open_dialog)
	get_window().files_dropped.connect(_on_files_dropped)
	%OpenButton.pressed.connect(open_rom_dialog)

func capture_rewind_state() -> Dictionary:
	return {
		"memory": memory.duplicate(),
		"registers": V.duplicate(),
		"display": display.duplicate(),
		"stack": stack.duplicate(),
		"quirks": quirks.duplicate(),
		
		"pc": pc,
		"I": I,
		"delay_timer": delay_timer,
		"sound_timer": sound_timer,
		"waiting_for_key": waiting_for_key,
		
		"last_pc": last_pc,
		"last_opcode": last_opcode,
		"trace": trace.duplicate(),
		
		"keys_used": keys_used.duplicate(),
		"announced_any_key": announced_any_key,
		
		"rng_seed": rng.seed,
		"rng_state": rng.state,
		
		"speed": instructions_per_frame,
		"display_wait": display_wait_enabled,
	}

func restore_rewind_state(snapshot: Dictionary) -> void:
	memory = snapshot["memory"].duplicate()
	V = snapshot["registers"].duplicate()
	display = snapshot["display"].duplicate()
	
	stack.assign(snapshot["stack"])
	trace.assign(snapshot["trace"])
	
	pc = snapshot["pc"]
	I = snapshot["I"]
	
	delay_timer = snapshot["delay_timer"]
	sound_timer = snapshot["sound_timer"]
	waiting_for_key = snapshot["waiting_for_key"]
	
	last_pc = snapshot["last_pc"]
	last_opcode = snapshot["last_opcode"]
	
	keys_used = snapshot["keys_used"].duplicate()
	announced_any_key = snapshot["announced_any_key"]
	
	rng.seed = snapshot["rng_seed"]
	rng.state = snapshot["rng_state"]
	
	instructions_per_frame = snapshot["speed"]
	display_wait_enabled = snapshot["display_wait"]
	
	speed_slider.set_value_no_signal(instructions_per_frame)
	wait_check.set_pressed_no_signal(display_wait_enabled)
	
	faulted = false
	drew_this_frame = false
	frame_blocked = false
	
	skip_breakpoint_pc = -1
	stopped_breakpoint_pc = -1
	status = ""
	
	quirks = snapshot["quirks"].duplicate()
	sync_compatibility_controls()
	
	beep.stop()

func remember_rewind_state() -> void:
	rewind_history.append(capture_rewind_state())
	
	if rewind_history.size() > REWIND_MAX_TICKS:
		rewind_history.pop_front()

func update_controls_label() -> void:
	if not rom_loaded:
		controls_label.text = "CONTROLS: No ROM loaded!"
		return
	
	var used: Array = keys_used.keys()
	used.sort()
	
	var text := "KEYS CHECKED BY THIS ROM:\n"
	
	if used.is_empty():
		text += "No specific keys detected yet."
	else:
		for index in range(used.size()):
			var chip8_key := int(used[index])
			var keyboard_key := OS.get_keycode_string(KEYMAP[chip8_key])
			
			if index > 0:
				if index % 4 == 0:
					text += "\n"
				else:
					text += "  "
			
			text += "%X -> %s" % [chip8_key, keyboard_key]
			
	if announced_any_key:
		text += "\nAlso uses ANY keypad key: press, then release."
	
	controls_label.text = text

func _on_rom_selected(index: int) -> void:
	if index < 0 or index >= rom_names.size():
		return
	var next_path: String = rom_paths[rom_names[index]]
	rom_picker.tooltip_text = rom_names[index]
	if next_path != current_rom:
		breakpoints.clear()
	current_rom = next_path
	rom_loaded = load_rom(current_rom)

func _on_display_wait_toggled(enabled: bool) -> void:
	display_wait_enabled = enabled
	
	mark_profile_custom()
	rewind_history.clear()
	
	status = "Custom compat. settings enabled."

func open_rom_dialog() -> void:
	paused = true
	open_dialog.popup_centered(Vector2i(720, 460))

func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if f.get_extension().to_lower() == "ch8":
			load_external_rom(f)
			return
	status = "Drop a .ch8 file in here."

func load_external_rom(path: String) -> void:
	if path != current_rom:
		breakpoints.clear()
	current_rom = path
	rom_loaded = load_rom(path)
	if rom_loaded:
		rom_picker.select(-1)
		paused = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if breakpoint_edit.has_focus():
				var field_rect := Rect2(
					Vector2.ZERO,
					breakpoint_edit.size
				)
				
				var mouse_position := (
					breakpoint_edit.get_local_mouse_position()
				)
				
				if not field_rect.has_point(mouse_position):
					breakpoint_edit.release_focus()
		return
	
	if not (event is InputEventKey):
		return
	
	if not event.pressed or event.echo:
		return
	
	if help_overlay.visible:
		if event.keycode == KEY_F1 or event.keycode == KEY_ESCAPE:
			show_help(false)
		return
	
	if breakpoint_edit.has_focus():
		if event.keycode == KEY_ESCAPE:
			breakpoint_edit.release_focus()
			get_viewport().set_input_as_handled()
		
		return
	
	match event.keycode:
		KEY_ESCAPE:
			reset_rom()
		
		KEY_P:
			toggle_pause()
		
		KEY_N:
			step_instruction()
		
		KEY_M:
			step_tick()
		
		KEY_H:
			mem_mode = (mem_mode + 1) % 3
		
		KEY_BRACKETLEFT:
			mem_mode = 2
			mem_base -= MEM_ROWS * MEM_COLS
		
		KEY_BRACKETRIGHT:
			mem_mode = 2
			mem_base += MEM_ROWS * MEM_COLS
		
		KEY_F1:
			show_help(true)
		
		KEY_O:
			open_rom_dialog()
		
		_:
			return
		
	get_viewport().set_input_as_handled()

func parse_breakpoint_address(raw_text: String) -> int:
	var cleaned := raw_text.strip_edges().to_upper()
	
	if cleaned.begins_with("0X"):
		cleaned = cleaned.substr(2)
	
	if cleaned.is_empty() or cleaned.length() > 3:
		return -1
	
	if cleaned.begins_with("+") or cleaned.begins_with("-"): ## Breakpoints CANT have these symbols in the front!
		return -1
	
	if not cleaned.is_valid_hex_number():
		return -1
	
	var address := cleaned.hex_to_int()
	
	if address < 0 or address + 1 >= memory.size():
		return -1
	
	return address

func _on_breakpoint_submitted(raw_text: String) -> void:
	var address := parse_breakpoint_address(raw_text)
	
	if address < 0:
		status = "Invalid breakpoint address."
	else:
		if breakpoints.has(address):
			breakpoints.erase(address)
			status = "Removed breakpoint at %03X" % address
		else:
			breakpoints[address] = true
			status = "Added breakpoint at %03X" % address
	breakpoint_edit.clear()
	breakpoint_edit.release_focus()

func breakpoints_text() -> String:
	var addresses: Array = breakpoints.keys()
	addresses.sort()
	
	if addresses.is_empty():
		return "-"
	
	var text := ""
	
	for address in addresses:
		text += "%03X " % int(address)
	
	return text 

func toggle_pause() -> void:
	if not rom_loaded:
		return
	
	if faulted:
		status = "Gotta reset the ROM before resuming after a fault!!"
		return
		
	if not paused:
		paused = true
		return
	
	var was_stopped_at_breakpoint := stopped_breakpoint_pc == pc 
	stopped_breakpoint_pc = -1
	
	paused = false
	status = ""
	
	if was_stopped_at_breakpoint and breakpoints.has(pc):
		skip_breakpoint_pc = pc

func step_instruction() -> void:
	if not rom_loaded or not paused or faulted:
		return
		
	drew_this_frame = false
	frame_blocked = false
	
	step()

func step_tick() -> void:
	if not rom_loaded or not paused or faulted:
		return
	
	if breakpoints.has(pc):
		skip_breakpoint_pc = pc
	
	run_frame()

func draw_screen() -> void:
	for sy in 32:
		for sx in 64:
			var on := display[sy * 64 + sx] == 1
			img.set_pixel(sx, sy, Color.WHITE if on else Color.BLACK)
	tex.update(img)

func read_keys() -> void:
	if breakpoint_edit.has_focus() or help_overlay.visible:
		keys.fill(0)
		return
	
	for k in 16:
		var keyboard_down := Input.is_physical_key_pressed(KEYMAP[k])
		var pad_down := pad_keys[k] == 1
		
		keys[k] = 1 if keyboard_down or pad_down else 0

func note_key(k: int) -> void:
	if keys_used.has(k):
		return
	keys_used[k] = true
	print("ROM check CHIP8 key %X -> press keypad '%s'" % [k, OS.get_keycode_string(KEYMAP[k])])

func _ready() -> void:
	%PowerButton.pressed.connect(func(): show_help(false))
	%PowerButton.focus_mode = Control.FOCUS_NONE
	%HelpButton.pressed.connect(func(): show_help(true))
	show_help(true)
	setup_screen()
	setup_sound()
	setup_picker()
	setup_open_dialog()
	setup_settings()
	setup_toolbar()
	setup_keypad()
	setup_compatibility_settings()
	_on_rom_selected(0)
	breakpoint_edit.text_submitted.connect(_on_breakpoint_submitted)

func _physics_process(_delta: float) -> void:
	read_keys()
	
	rewinding = (
		rom_loaded
		and not help_overlay.visible
		and not breakpoint_edit.has_focus()
		and Input.is_physical_key_pressed(KEY_B)
	)
	
	if rewinding:
		if not rewind_history.is_empty():
			var snapshot: Dictionary = rewind_history.pop_back()
			restore_rewind_state(snapshot)
	elif rom_loaded and not paused and not faulted:
		remember_rewind_state()
		run_frame()
	
	update_sound()
	draw_screen()
	update_debug()
	update_disassembly()
	update_memory_view()
	update_trace_view()
	update_controls_label()
	refresh_keypad()

func run_frame() -> void:
	if not rom_loaded or faulted:
		return
	
	drew_this_frame = false
	frame_blocked = false
	
	for instruction_number in range(instructions_per_frame):
		var bypass_breakpoint := pc == skip_breakpoint_pc
		skip_breakpoint_pc = -1
		
		if breakpoints.has(pc) and not bypass_breakpoint:
			paused = true
			stopped_breakpoint_pc = pc
			status = "Breakpoint at  %03X" % pc
			return
		
		step()
		
		if faulted:
			return
		
		if frame_blocked:
			break
	tick_timers()

func halt_machine(message: String) -> void:
	status = message
	faulted = true
	paused = true
	beep.stop()
	push_warning(message)

func tick_timers() -> void:
	if delay_timer > 0:
		delay_timer -= 1
	if sound_timer > 0:
		sound_timer -= 1

func show_help(show: bool) -> void:
	help_overlay.visible = show
	if show:
		paused_before_help = paused 
		paused = true
		beep.stop()
		pad_keys.fill(0)
	else:
		paused = paused_before_help

func update_sound() -> void:
	var should_beep := (
		sound_timer > 0
		and not paused
		and rom_loaded
		and not rewinding
	)
	if should_beep and not beep.playing:
		beep.play()
	elif not should_beep and beep.playing:
		beep.stop()

func update_debug() -> void:
	if not rom_loaded:
		debug_label.text = "NO ROM LOADED!!!!\n" + status
		return
	
	%PauseButton.text = "Resume" if paused else "Pause"
	
	
	var t := ""
	if rewinding:
		t += "REWINDING\n"
	else:
		t += "PAUSED\n" if paused else "RUNNING\n"
	if status != "":
		t += status + "\n"
	t += "\n"
	t += "PC %03X   I %03X\n" %  [pc, I]
	
	if last_pc >= 0:
		t += "LAST %03X: %04X   %s\n" % [last_pc, last_opcode, disassemble(last_opcode)]
	else:
		t += "LAST: none\n"
	
	t += "DT %02X    ST %02X\n\n" % [delay_timer, sound_timer]
	
	for r in 16:
		t += "V%X:%02X   " % [r, V[r]]
		if r % 4 == 3:
			t += "\n"
	
	t += "\nSTACK(%d):" % stack.size()
	for addr in stack:
		t += " %03X" % addr
	t += "\n"
	
	t += "HELD: " + held_keys_text() + "\n"
	t += "USES: " + used_keys_text() + "\n"
	
	t += "BREAKPOINTS: " + breakpoints_text() + "\n"
	
	debug_label.text = t

func update_disassembly() -> void:
	if not rom_loaded:
		disassembly_label.text = "NO PROGRAM!!"
		return
	
	var text := "INSTRUCTIONS\n\n"
	
	for row in range(8):
		var address := pc + row * 2
		if address < 0 or address + 1 >= memory.size():
			break
		
		var opcode := (memory[address] << 8) | memory[address + 1]
		var marker := ">" if row == 0 else " "
		
		text += "%s %03X %04X %s\n" % [marker, address, opcode, disassemble(opcode)]
		
		disassembly_label.text = text

func held_keys_text() -> String:
	var text := ""
	for k in 16:
		if keys[k] == 1:
			text += "%X " % k
	if text == "":
		return "-"
	return text 

func used_keys_text() -> String:
	var used: Array = keys_used.keys()
	used.sort()
	if used.is_empty():
		return "-"
	var text := ""
	for k in used:
		text += "%X " % k
	return text

func disassemble(opcode: int) -> String:
	var first := (opcode & 0xF000) >> 12
	var x := (opcode & 0x0F00) >> 8
	var y := (opcode & 0x00F0) >> 4
	var n := opcode & 0x000F
	var nn := opcode & 0x00FF
	var nnn := opcode & 0x0FFF
	
	match first:
		0x0:
			if opcode == 0x00E0:
				return "CLS"
			if opcode == 0x00EE:
				return "RET"
			return "SYS %03X" % nnn
		
		0x1:
			return "JP %03X" % nnn
		0x2:
			return "CALL %03X" % nnn
		0x3:
			return "SE V%X, %02X" % [x, nn]
		0x4:
			return "SNE V%X, %02X" % [x, nn]
		0x5:
			if n == 0:
				return "SE V%X, V%X" % [x, y]
		0x6:
			return "LD V%X, %02X" % [x, nn]
		0x7:
			return "ADD V%X, %02X" % [x, nn]
		0x8:
			match n:
				0x0:
					return "LD V%X, V%X" % [x, y]
				0x1:
					return 'OR V%X, V%X' % [x, y]
				0x2:
					return "AND V%X, V%X" % [x, y]
				0x3:
					return "XOR V%X, V%X" % [x, y]
				0x4:
					return "ADD V%X, V%X" % [x, y]
				0x5: 
					return "SUB V%X, V%X" % [x, y]
				0x6:
					return "SHR V%X, V%X" % [x, y]
				0x7:
					return "SUBN V%X, V%X" % [x, y]
				0xE:
					return "SHL V%X, V%X" % [x, y]
		0x9:
			if n == 0:
				return "SNE V%X, V%X" % [x, y]
		0xA:
			return "LD I, %03X" % nnn
		0xB:
			return "JP OFFSET, %03X" % nnn
		0xC:
			return "RND V%X, %02X" % [x, nn]
		0xD:
			return "DRW V%X, V%X, %X" % [x, y, n]
		0xE:
			match nn:
				0x9E:
					return "SKP V%X" % x
				0xA1:
					return "SKNP V%X" % x
		0xF:
			match nn:
				0x07:
					return "LD V%X, DT" % x
				0x0A:
					return "LD V%X, K"  % x
				0x15:
					return "LD DT, V%X" % x
				0x18:
					return "LD ST, V%X" % x
				0x1E:
					return "ADD I, V%X" % x
				0x29:
					return "LD F, V%X" % x
				0x33:
					return "LD B, V%X" % x
				0x55:
					return "LD [I], V%X" % x
				0x65:
					return "LD V%X, [I]" % x
	return "UNKNOWN %04X" % opcode

func step() -> void:
	if not rom_loaded or faulted:
		return
	
	if pc < 0 or pc + 1 >= memory.size():
		halt_machine("PC outside memory: %04X" % pc)
		return
		
	var opcode := (memory[pc] << 8) | memory[pc + 1]
	if display_wait_enabled and (opcode & 0xF000) == 0xD000 and drew_this_frame:
		frame_blocked = true 
		return
	last_pc = pc
	last_opcode = opcode
	trace.append((last_pc << 16) | opcode)
	if trace.size() > TRACE_MAX:
		trace.pop_front()
	pc += 2
	
	var first := (opcode & 0xF000) >> 12
	var x := (opcode & 0x0F00) >> 8 
	var y := (opcode & 0x00F0) >> 4
	var n := opcode & 0x000F
	var nn := opcode & 0x00FF
	var nnn := opcode & 0x0FFF
	
	match first:
		0x0:
			if opcode == 0x00E0:
				display.fill(0)
			elif opcode == 0x00EE:
				if stack.is_empty():
					halt_machine("Return with empty stack at %03X" % last_pc)
					return
					
				pc = stack.pop_back()
		0x1:
			pc = nnn
		0x2:
			stack.append(pc)
			pc = nnn
		0x3:
			if V[x] == nn:
				pc += 2
		0x4:
			if V[x] != nn:
				pc += 2
		0x5:
			if V[x] == V[y]:
				pc += 2
		0x6:
			V[x] = nn 
		0x7:
			V[x] = (V[x] + nn) & 0xFF
		0x8:
			match n:
				0x0:
					V[x] = V[y]
				0x1:
					V[x] = V[x] | V[y]
					if quirks["vf_reset"]:
						V[0xF] = 0
				0x2:
					V[x] = V[x] & V[y]
					if quirks["vf_reset"]:
						V[0xF] = 0
				0x3:
					V[x] = V[x] ^ V[y]
					if quirks["vf_reset"]:
						V[0xF] = 0
				0x4:
					var sum := V[x] + V[y]
					var flag := 1 if sum > 255 else 0
					V[x] = sum & 0xFF
					V[0xF] = flag
				0x5:
					var diff := V[x] - V[y]
					var flag := 1 if V[x] >= V[y] else 0
					V[x] = diff & 0xFF
					V[0xF] = flag
				0x7:
					var diff := V[y] - V[x]
					var flag := 1 if V[y] >= V[x] else 0 
					V[x] = diff & 0xFF
					V[0xF] = flag
				0x6:
					var right_source: int
					
					if quirks["shift_vy"]:
						right_source = V[y]
					else:
						right_source= V[x]
					
					var flag := right_source & 1
					
					V[x] = right_source >> 1
					V[0xF] = flag
				0xE:
					var left_source: int
					
					if quirks["shift_vy"]:
						left_source = V[y]
					else: 
						left_source = V[x]
					
					var flag := (left_source >> 7) & 1
					
					V[x] = (left_source << 1) & 0xFF
					V[0xF] = flag
				_:
					halt_machine("Unknown opcode %04X at %03X" % [opcode, last_pc])
		0x9:
			if V[x] != V[y]:
				pc += 2
		0xA:
			I = nnn
		0xB:
			var jump_offset: int
			
			if quirks["jump_v0"]:
				jump_offset = V[0]
			else:
				jump_offset = V[x]
			
			pc = nnn + jump_offset
		0xC:
			V[x] = rng.randi_range(0, 255) & nn
		0xD:
			var px := V[x] % 64
			var py := V[y] % 32
			V[0xF] = 0
			drew_this_frame = true
			for row in n:
				var sprite_byte := memory[I + row]
				for col in 8:
					var bit := (sprite_byte >> (7 - col)) & 1
					if bit == 0:
						continue
					var sx := px + col
					var sy := py + row
					if quirks["clip"]:
						if sx >= 64 or sy >= 32:
							continue
					else:
						sx %= 64
						sy %= 32
					var idx = sy * 64 + sx
					if display[idx] == 1:
						V[0xF] = 1
					display[idx] = display[idx] ^ 1

		0xE:
			note_key(V[x] & 0xF)
			match nn:
				0x9E:
					if keys[V[x] & 0xF] == 1:
						pc += 2
				0xA1:
					if keys[V[x] & 0xF] == 0:
						pc += 2
				_:
					halt_machine("Unknown opcode %04X at %03X" % [opcode, last_pc])
		0xF:
			match nn:
				0x0A:
					if announced_any_key == false:
						announced_any_key = true
						print("Waiting for keys (FX0A)")
					if waiting_for_key == -1:
						for i in range(16):
							if keys[i] == 1:
								waiting_for_key = i
								break
						pc -= 2
					else:
						if keys[waiting_for_key] == 0:
							V[x] = waiting_for_key
							waiting_for_key = -1
						else:
							pc -= 2
				0x1E:
					I = (I + V[x]) & 0xFFF
				0x07:
					V[x] = delay_timer
				0x15:
					delay_timer = V[x]
				0x18:
					sound_timer = V[x]
				0x29:
					I = FONT_START + (V[x] & 0xF) * 5
				0x33:
					memory[I] = V[x] / 100
					memory[I + 1] = (V[x] / 10) % 10
					memory[I + 2] = V[x] % 10
				0x55: ## Stores V0 through Vx in memory
					for register_index in range(x + 1):
						memory[I + register_index] = V[register_index]
					if quirks["memory_increment"]:
						I += x + 1
				0x65: ## Loads V0 through Vx from memory
					for register_index in range(x + 1):
						V[register_index] = memory[I + register_index]
					if quirks["memory_increment"]:
						I += x + 1
				_:
					halt_machine("Unknown opcode %04X at %03X" % [opcode, last_pc])
