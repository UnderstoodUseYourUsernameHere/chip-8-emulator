Made in Godot 4

## CHIP-8 Emulator (Interpreter if you want to be super semantic.)

What is a CHIP-8 Interpreter you may be asking? Or not? CHIP-8 is an interpreted programming language, developed by Joseph Weisbecker on his 1802 microprocessor. It was initially used on the COSMAC VIP and Telmac 1800, which were 8-bit microcomputers made in the mid-1970s.
This project emulates the CHIP-8 cpu, memory, etc, which allows you to play the ROMs that run on the associated devices, just like any emulator! 


## How to use

Itch demo link (you dont download anything this way, which i find way better): [insert your itch.io link here]

Or, you can do this:

    Open Godot 4
    Open this project folder
    Press Play (▶) at the top

## How to Play

    Load a Game: Pick a cartridge from the dropdown menu, or click "Open ROM" to upload your own .ch8 file!
    The Keypad: The original CHIP-8 had a 16-key hex pad. It's mapped to your keyboard like this:
        1 2 3 C -> 1 2 3 4
        4 5 6 D -> Q W E R
        7 8 9 E -> A S D F
        A 0 B F -> Z X C V
    Controls Panel: Don't know how to play a game? Look at the "Controls" panel! The emulator actively watches the CPU to see which keys the game is checking and tells you what to press.
    On-Screen Keypad: You can also just click the on-screen keypad. Keys light up amber when the game checks them, and green when you press them.

## Features:

    A fully functional 1977 CPU: Emulates memory, registers, timers, and the XOR-based graphics of the original CHIP-8.
	
    Live Debugger: A full suite of developer tools built right into the UI. You can see the PC, Index register, V0-VF registers, and the Stack updating 60 times a second. 
	
    Disassembler & Trace Log: The "Code" tab translates raw hex into readable assembly instructions (like LD V0, 0C), and the "Trace" tab shows you the exact history of the last 32 instructions the CPU executed, though "readable" is still a bit of a stretch, its better than just machine code, i hope.
	
    Execution Controls: Press P to pause. While paused, press N to step forward exactly one instruction, or M to step one full frame. You can even type in a hex address to set a Breakpoint and the emulator will halt when it reaches it! (It will *keep* pausing when it reaches it so make sure you type the hexcode BACK in to remove it)
	
    Hold-to-Rewind: Made a mistake in Pong or Brix? Hold B to literally rewind the emulator state up to 10 seconds into the past. (WOW, this is like wally west!!!!!!!!)
	
    Memory Viewer: A live hex-dump of all 4096 bytes of RAM. You can follow the Program Counter, follow the Index register (to see sprite data), or page through it manually.
	
    Compatibility Profiles: Not all CHIP-8 games were coded the same. The settings tab lets you toggle historical quirks (like VF reset, shifting behavior, and display-wait) and adjust the CPU speed so games from different eras run perfectly. (Though the cpu speed is a slider so accuracy is... meh)
	
    Custom ROM Uploads: Drag and drop any .ch8 file onto the screen, or use the Open button to load files directly from your computer (works in the browser too!).
	
    VIP-Inspired Boot: Starts up in a paused "Monitor" state inspired by the original COSMAC VIP computer. (Though inspired is a stretch, i just made it because it looked kewl)

This is hopefully pretty simple! Coded in GDScript, obviously, using Godot 4.
Credits

    Test ROMs: Timendus's CHIP-8 Test Suite (Corax+, Flags, Quirks, Keypad).
    Documentation: Tobias Langhoff's Guide & Cowgod's CHIP-8 Technical Reference. (These helped a ton)
    Games: Public domain CHIP-8 ROMs (Brix, Cave, etc.).
    SFX: Its... One square beeper made in code! I didnt even make a node for this! (This is not impressive at all, obviously)
