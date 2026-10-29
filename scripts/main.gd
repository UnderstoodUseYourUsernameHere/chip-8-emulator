extends Control

@onready var rom_picker: OptionButton = $HBoxContainer/VBoxContainer/RomPicker
@onready var screen: TextureRect = $HBoxContainer/Screen

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
	"Cave": "res://games/Cave.ch8",
}

var instructions_per_frame := 11
var current_rom := ""
var paused := false

var stack: Array[int] = []
var delay_timer := 0
var sound_timer := 0
var rom_loaded := false

var img: Image
var tex: ImageTexture

var display := PackedByteArray()
var drew_this_frame := false
var glow := PackedFloat32Array() 
var glow_decay := 0.10


var beep := AudioStreamPlayer.new()

var memory := PackedByteArray()
var V := PackedByteArray()  ## Registers from VO to VF
var I := 0 ## This is the index register
var pc := 0x200 ## pc stands for program counter, if you arent in the know. 

func load_rom(path: String) -> bool:
	memory.resize(4096) ## Resets everything to a clean slate
	memory.fill(0)
	V.resize(16)
	V.fill(0)
	display.resize(64 * 32)
	display.fill(0)
	stack.clear()
	keys.resize(16) 
	keys.fill(0)
	keys_used.clear()
	announced_any_key = false
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
	glow.resize(64 * 32)
	glow.fill(0)

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
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ESCAPE:
			rom_loaded = load_rom(current_rom)
		KEY_P:
			paused = not paused

func draw_screen() -> void:
	for sy in 32:
		for sx in 64:
			var idx := sy * 64 + sx
			if display[idx] == 1:
				glow[idx] = 1.0
			else:
				glow[idx] *= glow_decay
			var b := glow[idx]
			img.set_pixel(sx, sy, Color(b, b, b))
	tex.update(img)

func read_keys() -> void:
	for k in 16:
		keys[k] = 1 if Input.is_physical_key_pressed(KEYMAP[k]) else 0

func note_key(k: int) -> void:
	if keys_used.has(k):
		return
	keys_used[k] = true
	print("ROM check CHIP8 key %X -> press keypad '%s" % [k, OS.get_keycode_string(KEYMAP[k])])

func _ready() -> void:
	setup_screen()
	setup_sound()
	setup_picker()
	_on_rom_selected(0)

func _physics_process(_delta: float) -> void:
	read_keys()
	if not rom_loaded:
		return
		
	if not paused:
		drew_this_frame = false
		for i in instructions_per_frame:
			step()
			if drew_this_frame:
				break
			
		if delay_timer > 0:
			delay_timer -= 1
		if sound_timer > 0:
			sound_timer -= 1
			
		var should_beep := sound_timer > 0 and not paused
		if should_beep and not beep.playing:
			beep.play()
		elif not should_beep and beep.playing:
			beep.stop()
		draw_screen()

func step() -> void:
	if not rom_loaded:
		return
	
	if pc < 0 or pc + 1 >= memory.size():
		push_error("Program counter outside memory: 0x%03X" % pc)
		rom_loaded = false
		return
		
	var opcode := (memory[pc] << 8) | memory[pc + 1]
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
					push_error("Return with empty stack at 0x%03X" % (pc- 2))
					rom_loaded = false
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
					print("UNKNOWN %04X" % opcode)
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
					print("UNKNOWN %04X" % opcode)
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
					print("UNKNOWN %04X" % opcode)
