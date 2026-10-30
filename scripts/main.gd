extends Control

@onready var rom_picker: OptionButton = $%RomPicker
@onready var screen: TextureRect = $%Screen
@onready var debug_label: Label = $%DebugLabel
@onready var disassembly_label: Label = $%DisassemblyLabel
@onready var breakpoint_edit: LineEdit = $%BreakpointEdit

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

const ROMS := {
	"IBM Logo": "res://roms/2-ibm-logo.ch8",
	"Corax+ Test": "res://roms/3-corax+.ch8",
	"Quirks Test": "res://roms/5-quirks.ch8",
	"Keypad Test": "res://roms/6-keypad.ch8",
	"Brix": "res://games/Brix.ch8",
	"Flags Test": "res://roms/4-flags.ch8",
	"Beep Test": "res://roms/7-beep.ch8",
	"Cave": "res://games/Cave.ch8",
}

var instructions_per_frame := 11
var current_rom := ""
var paused := false
var last_opcode := 0 ## These ones are something im not sure of, hopefully they work as i think they will
var last_pc := 0
var status := ""
var faulted := false
var frame_blocked := false

var breakpoints := {}
var skip_breakpoint_pc := -1 

var stack: Array[int] = []
var delay_timer := 0
var sound_timer := 0
var rom_loaded := false

var img: Image
var tex: ImageTexture

var display := PackedByteArray()
var display_wait_enabled := true
var drew_this_frame := false


var beep := AudioStreamPlayer.new()

var memory := PackedByteArray()
var V := PackedByteArray()  ## Registers from VO to VF
var I := 0 ## This is the index register
var pc := 0x200 ## pc stands for program counter, if you arent in the know. 

func load_rom(path: String) -> bool:
	memory.resize(4096) ## Resets everything to a clean slate
	memory.fill(0)
	status = ""
	V.resize(16)
	V.fill(0)
	display.resize(64 * 32)
	display.fill(0)
	stack.clear()
	keys.resize(16) 
	keys.fill(0)
	keys_used.clear()
	announced_any_key = false
	faulted = false
	frame_blocked = false
	skip_breakpoint_pc = -1
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

func setup_screen() -> void:
	img = Image.create_empty(64, 32, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	tex = ImageTexture.create_from_image(img)
	screen.texture = tex
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


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
	for rom_name in ROMS.keys():
		rom_picker.add_item(rom_name)
	rom_picker.item_selected.connect(_on_rom_selected)
	rom_picker.focus_mode = Control.FOCUS_NONE

func _on_rom_selected(index: int) -> void:
	current_rom = ROMS.values()[index]
	rom_loaded = load_rom(current_rom)

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
	
	if breakpoint_edit.has_focus():
		if event.keycode == KEY_ESCAPE:
			breakpoint_edit.release_focus()
			get_viewport().set_input_as_handled()
		
		return
	
	match event.keycode:
		KEY_ESCAPE:
			rom_loaded = load_rom(current_rom)
		
		KEY_P:
			toggle_pause()
		
		KEY_N:
			step_instruction()
		
		KEY_M:
			step_tick()
		
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
	
	var was_stopped_at_breakpoint := status.begins_with("Breakpoint at")
	
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
	if breakpoint_edit.has_focus():
		keys.fill(0)
		return
	
	for k in 16:
		keys[k] = 1 if Input.is_physical_key_pressed(KEYMAP[k]) else 0

func note_key(k: int) -> void:
	if keys_used.has(k):
		return
	keys_used[k] = true
	print("ROM check CHIP8 key %X -> press keypad '%s'" % [k, OS.get_keycode_string(KEYMAP[k])])

func _ready() -> void:
	setup_screen()
	setup_sound()
	setup_picker()
	_on_rom_selected(0)
	breakpoint_edit.text_submitted.connect(_on_breakpoint_submitted)

func _physics_process(_delta: float) -> void:
	read_keys()
	if rom_loaded and not paused:
		run_frame()
	update_sound()
	draw_screen()
	update_debug()
	update_disassembly()

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

func update_sound() -> void:
	var should_beep := sound_timer > 0 and not paused and rom_loaded
	if should_beep and not beep.playing:
		beep.play()
	elif not should_beep and beep.playing:
		beep.stop()

func update_debug() -> void:
	if not rom_loaded:
		debug_label.text = "NO ROM LOADED!!!!\n" + status
		return
	
	var t := ""
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
					V[0xF] = 0
				0x2:
					V[x] = V[x] & V[y]
					V[0xF] = 0
				0x3:
					V[x] = V[x] ^ V[y]
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
					var flag := V[y] & 1
					V[x] = (V[y] >> 1) & 0xFF
					V[0xF] = flag
				0xE:
					var flag := (V[y] >> 7) & 1
					V[x] = (V[y] << 1) & 0xFF
					V[0xF] = flag
				_:
					halt_machine("Unknown opcode %04X at %03X" % [opcode, last_pc])
		0x9:
			if V[x] != V[y]:
				pc += 2
		0xA:
			I = nnn
		0xB:
			pc = nnn + V[0]
		0xC:
			V[x] = randi_range(0, 255) & nn
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
					if sx >= 64 or sy >= 32:
						continue
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
					for i in range(x + 1):
						memory[I] = V[i]
						I += 1
				0x65: ## Loads V0 through Vx from memory
					for i in range(x + 1):
						V[i] = memory[I]
						I += 1
				_:
					halt_machine("Unknown opcode %04X at %03X" % [opcode, last_pc])
