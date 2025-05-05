package main

import fmt "core:fmt"
import rlb "vendor:raylib"
import mth "core:math"
import os "core:os"
import js "core:encoding/json"
import str "core:strings"

Collision_Type :: enum {
	Bottom,
	Top,
	Left,
	Right,
	Special
}

Projectile :: struct {
	old_pos: rlb.Vector2,
	pos: rlb.Vector2,
	vel: rlb.Vector2,
	airborn: bool,
	lifetime: i32
}

Screen :: struct {
	tiles: [28][32]byte,
	player_start: rlb.Vector2,
	coins: i32
}

JSON_Screen :: struct {
	tiles: [28 * 32]byte,
	player_start: rlb.Vector2
}

Entity :: struct {
	position: rlb.Vector2,
	old_position: rlb.Vector2,

	velocity: rlb.Vector2, 
	flip: bool,
	airborn: bool,
	moving: bool,
	duck: bool,

	tail_pos: rlb.Vector2,
	cape_pos: [4]rlb.Vector2,

	tail_color: rlb.Color,
	tail_accent_color: rlb.Color,
	cape_color: rlb.Color,

	player_model_index: i32,

	edge_run: i32,

	headbob: bool
}

make_empty_screen :: proc(screen: Screen) -> Screen {
	screen := screen
    for y : i32 = 0; y < 28; y += 1 {
        for x : i32 = 0; x < 32; x += 1 {
        	screen.tiles[y][x] = 0
        	if y == 27 {
				screen.tiles[y][x] = 1			
			}
        }
    }

    screen.player_start = {0, 0}
    return screen
}

screen_from_file :: proc(file_path: cstring) -> (screen: Screen) {
    file_data, ok := os.read_entire_file_from_filename(string(file_path))

    if !ok {
    	fmt.printfln("'%s' does not exist or is corrupted", string(file_path))

        return make_empty_screen(screen)
    }

    room_parser := js.make_parser(file_data, js.DEFAULT_SPECIFICATION, true)
    room_data, ok2 := js.parse_object(&room_parser)

    if ok2 != js.Error.None {
    	fmt.printfln("'%s' does not exist or is corrupted", string(file_path))

        return make_empty_screen(screen)
    }

    for y : i32 = 0; y < 28; y += 1 {
        for x : i32 = 0; x < 32; x += 1 {
        	screen.tiles[y][x] = (u8)(room_data.(js.Object)["tiles"].(js.Array)[(y * 32) + x].(js.Integer))

        	if screen.tiles[y][x] == COIN_BLOCK_I {
        		screen.coins += 1
        	}

        	screen.player_start[0] = f32(room_data.(js.Object)["player_start"].(js.Array)[0].(js.Float))
        	screen.player_start[1] = f32(room_data.(js.Object)["player_start"].(js.Array)[1].(js.Float))
        }
    }

    return
}

screen_to_file :: proc(file_path: cstring, screen: Screen) {
	tiles : [28 * 32]byte
	for y := 0; y < 28; y += 1 {
		for x := 0; x < 32; x += 1 {
			tiles[(y * 32) + x] = screen.tiles[y][x]
		}
	}

	m_options : js.Marshal_Options

	m_screen := JSON_Screen {tiles, screen.player_start}

	marshaled_screen, ok3 := js.marshal(m_screen, m_options)

	os.write_entire_file(string(file_path), marshaled_screen)
}

// TODO: make entity
player_state  :: proc(player: ^Entity, integer_time: i32) {
	using player 
	if edge_run > 0 {
		edge_run -= 1
	}

	if airborn {
		velocity[1] += 0.7
	}

	if ((integer_time % 4 == 0) if moving else (integer_time % 30 == 0)) {
		headbob = !(headbob)
	}

	velocity[0] = clamp(velocity[0], -3, 3)		

	tail_pos[0] = f32(mth.lerp(f64(tail_pos[0]), f64(position[0] + (velocity[0] + 10 if flip else velocity[0] - 4) * 1.25), 0.4))
	tail_pos[1] = f32(mth.lerp(f64(tail_pos[1]) + (1 if duck else 0), f64(position[1] - velocity[1] + (14)), 0.5))

	cape_pos[0] = position + {5 if flip else 3, 11}

	// Uses connected bones
	for i := 1; i < len(cape_pos); i += 1 {
		cape_pos[i] = {0, f32(i) * -0.01} + {f32(mth.lerp(f64(cape_pos[i][0]), f64(cape_pos[i-1][0]), 0.35)), f32(mth.lerp(f64(cape_pos[i][1]), f64(cape_pos[i-1][1]), 0.35))}
	}
}

player_input :: proc(player: ^Entity, integer_time: i32) {
	using player 

	// Jump
	if rlb.IsGamepadButtonPressed(0, rlb.GamepadButton.RIGHT_FACE_DOWN) && (!(airborn) || edge_run > 0) {
		velocity[1] = -4.5
	}

	// Tail whip, TODO: idk like maybe add some projectile?
	if rlb.IsGamepadButtonPressed(0, rlb.GamepadButton.RIGHT_FACE_LEFT) {
		tail_pos = (position) + ({-8, -3} if flip else {8, -3}) 
		flip = !(flip)
	}

	if rlb.IsGamepadButtonDown(0, rlb.GamepadButton.LEFT_FACE_LEFT) && !(duck) {
		velocity[0] -= 0.66
		flip = true
	}

	if rlb.IsGamepadButtonDown(0, rlb.GamepadButton.LEFT_FACE_RIGHT) && !(duck) {
		velocity[0] += 0.66
		flip = false
	}				

	// Check left/right movement input
	if (!rlb.IsGamepadButtonDown(0, rlb.GamepadButton.LEFT_FACE_RIGHT) && !rlb.IsGamepadButtonDown(0, rlb.GamepadButton.LEFT_FACE_LEFT)) || duck {
		velocity[0] *= 0.65

		moving = false
	} else {
		moving = true
	}

	if rlb.IsGamepadButtonDown(0, rlb.GamepadButton.LEFT_FACE_DOWN) {
		duck = true
		if airborn {
			velocity += {0, 1}
		}
	} else {
		duck = false
	}

}

// TODO: just change to entity
draw_player :: proc(entity_atlas: rlb.Texture2D, player: Entity, integer_time: i32) {
	using player

	// Draw cape, pixels are stars in cape
	for i := 1; i < len(cape_pos); i += 1 {
		rlb.DrawLineEx(cape_pos[i-1], cape_pos[i], 8 - f32(i), cape_color)
		rlb.DrawPixelV(cape_pos[i-1] + {1, 1.25}, YELLOW)
		rlb.DrawPixelV(cape_pos[i-1] - {1.25, 1}, YELLOW)
		rlb.DrawPixelV(cape_pos[i-1] + {1.25, 1.25}, YELLOW)
		rlb.DrawPixelV(cape_pos[i-1] - {1, 1}, YELLOW)		
	}
	
	// Tail
	rlb.DrawLineBezier(position + {4, 11}, tail_pos, 3, tail_color)
	rlb.DrawLineBezier(position + {4, 12}, tail_pos + {0, 1}, 1.25, tail_accent_color)

	// Head
	draw_indexed_pro(entity_atlas, 1 + (16 * player_model_index), i32(tail_pos[0]), i32(tail_pos[1]), false, 0, {3, 7})

	// Body
	draw_indexed(entity_atlas, (16 * player_model_index) + (8 + ((integer_time & 10) % 3) if moving else 8), i32(position[0]), i32(position[1]) + (9 if duck else 8), flip)
	draw_indexed(entity_atlas, (16 * player_model_index), i32(position[0]), i32(position[1] + 4) if duck else i32(position[1] + (1 if headbob else 0)), flip)

}

// TODO: change to include entities in general?
physics_player :: proc(screen: ^Screen, old_pos: ^rlb.Vector2, pos: ^rlb.Vector2, vel: ^rlb.Vector2, airborn: ^bool, edge_run: ^i32) {
	old_pos^ = pos^
	old_vel := vel

	pos^ += vel^

	pos^[0] = clamp(pos^[0], 0, 8 * 31)
	pos^[1] = clamp(pos^[1], 0, 8 * 27)

	airborn^ = true

	if vel^[1] >= 0 {
		for i := i32(mth.ceil(old_pos^[1] / 8)); i < i32(mth.floor(pos^[1] / 8 + 1)); i += 1 {

			// a := clamp(i32(mth.floor(pos^[0])) / 8, 0, 31)
			b := clamp(i32(mth.floor(pos^[0] + 1)) / 8, 0, 31)
			c := clamp(i32(mth.floor(pos^[0] + 7)) / 8, 0, 31)

			p := clamp(i32(i + 2), 0, 27)

			cb := tile_behavior[screen.tiles[p][c]]

			tile_behavior_funcs[cb](f32(i), Collision_Type.Top, c, p, screen, old_pos, pos, vel, airborn, edge_run)

			// ab := tile_behavior[screen.tiles[p][a]]

			// tile_behavior_funcs[ab](f32(i), Collision_Type.Top, a, p, screen, old_pos, pos, vel, airborn, edge_run)

			bb := tile_behavior[screen.tiles[p][b]]

			tile_behavior_funcs[bb](f32(i), Collision_Type.Top, b, p, screen, old_pos, pos, vel, airborn, edge_run)
		}	
	} else  {
		for i := i32(mth.floor(old_pos^[1] / 8)); i >= i32(mth.ceil(pos^[1] / 8)); i -= 1 {

			// a := clamp(i32(mth.floor(pos^[0])) / 8, 0, 31)
			b := clamp(i32(mth.floor(pos^[0] + 1 )) / 8, 0, 31)
			c := clamp(i32(mth.floor(pos^[0] + 7)) / 8, 0, 31)

			p := clamp(i32(i-1), 0, 27)

			cb := tile_behavior[screen.tiles[p][c]]

			tile_behavior_funcs[cb](f32(i), Collision_Type.Bottom, c, p, screen, old_pos, pos, vel, airborn, edge_run)

			bb := tile_behavior[screen.tiles[p][b]]

			tile_behavior_funcs[bb](f32(i), Collision_Type.Bottom, b, p, screen, old_pos, pos, vel, airborn, edge_run)

		}	
	}	
	if vel^[0] >= 0 {
		for i := i32(mth.ceil(old_pos^[0] / 8 - 1)); i < i32(mth.floor(pos^[0] / 8 + 1)); i += 1 {
			a := clamp(i32(mth.floor((pos^[1]) / 8)), 0, 27)
			b := clamp(i32(mth.floor((pos^[1] + 8) / 8)), 0, 27)	

			p := clamp(i32(i+1), 0, 31)

			ab := tile_behavior[screen.tiles[a][p]]

			tile_behavior_funcs[ab](f32(i), Collision_Type.Left, p, a, screen, old_pos, pos, vel, airborn, edge_run)

			bb := tile_behavior[screen.tiles[b][p]]

			tile_behavior_funcs[bb](f32(i), Collision_Type.Left, p, b, screen, old_pos, pos, vel, airborn, edge_run)
		}	
	} else {
		for i := i32(mth.floor(old_pos^[0] / 8)+1); i >= i32(mth.ceil(pos^[0] / 8)); i -= 1 {

			a : i32 = clamp(i32(mth.floor((pos^[1]) / 8)), 0, 27)
			b : i32 = clamp(i32(mth.floor((pos^[1] + 8) / 8)), 0, 27)		

			p := clamp(i32(i-1), 0, 31)

			ab := tile_behavior[screen.tiles[a][p]]

			tile_behavior_funcs[ab](f32(i), Collision_Type.Right, p, a, screen, old_pos, pos, vel, airborn, edge_run)

			bb := tile_behavior[screen.tiles[b][p]]	

			tile_behavior_funcs[bb](f32(i), Collision_Type.Right, p, b, screen, old_pos, pos, vel, airborn, edge_run)
		}	
	}


	if pos^[0] <= 0 || pos^[0] >= 8 * 31 {
		vel^[0] = 0
	}
	if pos^[1] <= 0 || pos^[1] >= 8 * 27 {
		vel^[1] = 0
	}
}

tile_behavior_nil :: proc(i: f32, collision: Collision_Type, t_x: i32, t_y: i32, screen: ^Screen, old_pos: ^rlb.Vector2, pos: ^rlb.Vector2, vel: ^rlb.Vector2, airborn: ^bool, edge_run: ^i32)
{

}

tile_behavior_oneway :: proc(i: f32, collision: Collision_Type, t_x: i32, t_y: i32,  screen: ^Screen, old_pos: ^rlb.Vector2, pos: ^rlb.Vector2, vel: ^rlb.Vector2, airborn: ^bool, edge_run: ^i32)
{
	if collision == Collision_Type.Top {
		airborn^ = false
		pos^[1] = i * 8
		vel^[1] = 0
		edge_run^ = 4
	}
}

tile_behavior_full_collision :: proc(i: f32, collision: Collision_Type, t_x: i32, t_y: i32,  screen: ^Screen, old_pos: ^rlb.Vector2, pos: ^rlb.Vector2, vel: ^rlb.Vector2, airborn: ^bool, edge_run: ^i32)
{
	l_or_r := (collision == Collision_Type.Left || collision == Collision_Type.Right)

	if l_or_r {
		pos^[0] = i * 8
		vel^[0] = 0		
	} else {
		if collision == Collision_Type.Top {
			airborn^ = false
			edge_run^ = 4

			pos^[1] = i * 8
			vel^[1] = 0				
		} else if collision == Collision_Type.Bottom {
			pos^[1] = i * 8
			vel^[1] = 0			
		}
	
	}
}

tile_behavior_bounce :: proc(i: f32, collision: Collision_Type, t_x: i32, t_y: i32,  screen: ^Screen, old_pos: ^rlb.Vector2, pos: ^rlb.Vector2, vel: ^rlb.Vector2, airborn: ^bool, edge_run: ^i32) {
	if collision == Collision_Type.Top {
	
		if vel^[1] >= 0 {
			pos^[1] = f32(i) * 8		
			vel^[1] = min(-mth.abs(vel^[1]) * 1.1, -6)
			edge_run^ = 4			
		}

	}
}

tile_behavior_collect_coin :: proc(i: f32, collision: Collision_Type, t_x: i32, t_y: i32,  screen: ^Screen, old_pos: ^rlb.Vector2, pos: ^rlb.Vector2, vel: ^rlb.Vector2, airborn: ^bool, edge_run: ^i32) {
	screen^.tiles[t_y][t_x] = 0
	screen^.coins -= 1
}

// TODO: merge with draw_indexed_pro()
draw_indexed_pro_scaled :: proc(atlas: rlb.Texture2D, index: i32, pos_x: i32, pos_y: i32, flip: bool, rotate: f32, origin: rlb.Vector2, scale: f32) {
	rlb.SetShapesTexture(atlas, {f32((index - 7) if flip else index & 7) * 8, f32((index &~ 7) >> 3) * 8, -8 if flip else 8, 8})
	rlb.DrawRectanglePro({f32(pos_x), f32(pos_y), scale, scale}, origin, rotate, rlb.WHITE)

	rlb.SetShapesTexture(atlas, {0, 0, 0, 0})
}

draw_indexed_pro :: proc(atlas: rlb.Texture2D, index: i32, pos_x: i32, pos_y: i32, flip: bool, rotate: f32, origin: rlb.Vector2) {
	rlb.SetShapesTexture(atlas, {f32((index - 7) if flip else index & 7) * 8, f32((index &~ 7) >> 3) * 8, -8 if flip else 8, 8})
	rlb.DrawRectanglePro({f32(pos_x), f32(pos_y), 8, 8}, origin, rotate, rlb.WHITE)

	rlb.SetShapesTexture(atlas, {0, 0, 0, 0})
}

draw_indexed :: proc(atlas: rlb.Texture2D, index: i32, pos_x: i32, pos_y: i32, flip: bool) {
	rlb.SetShapesTexture(atlas, {f32((index - 7) if flip else index & 7) * 8, f32((index &~ 7) >> 3) * 8, -8 if flip else 8, 8})
	rlb.DrawRectangle(pos_x, pos_y, 8, 8, rlb.WHITE)

	rlb.SetShapesTexture(atlas, {0, 0, 0, 0})
}

DARK_GRAY :: rlb.Color {64, 64, 64, 255}
WHITE :: rlb.Color {255, 255, 255, 255}
BLUE :: rlb.Color {128, 128, 255, 255}
YELLOW :: rlb.Color {255, 255, 0, 255}
RED :: rlb.Color {255, 64, 64, 255}
GREEN :: rlb.Color {128, 255, 64, 255}
LIGHT_BLUE :: rlb.Color {128, 255, 255, 255}
PINK :: rlb.Color {255, 128, 255, 255}
NONE :: rlb.Color {0, 0, 0, 0}

TILE_TYPES :: 23
TILE_BEHAVIOR_FUNCS :: 5 

SWITCH_BLOCK_I :: 20
COIN_BLOCK_I :: 22
DOOR_BLOCK_I :: 11

tile_behavior_funcs := [TILE_BEHAVIOR_FUNCS](proc(i: f32, collision: Collision_Type, t_x: i32, t_y: i32,  screen: ^Screen, old_pos: ^rlb.Vector2, pos: ^rlb.Vector2, vel: ^rlb.Vector2, airborn: ^bool, edge_run: ^i32)) {
	tile_behavior_nil, tile_behavior_oneway, tile_behavior_full_collision, tile_behavior_bounce, tile_behavior_collect_coin
}
tile_behavior := [TILE_TYPES]byte {0, 2, 1, 2, 2, 2, 1, 1, 2, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 3, 2, 0, 4}
tile_sprite := [TILE_TYPES]byte {0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21}

main :: proc() {
	rlb.InitWindow(768, 672, "Frappa")
	rlb.GuiLoadStyle("style_lavanda.rgs")

	rlb.SetTargetFPS(30)

	// 256x224 NES resolution(?)
	render_target := rlb.LoadRenderTexture(256, 224)

	entity_atlas := rlb.LoadTexture("entity_atlas.png")
	tile_atlas := rlb.LoadTexture("tile_atlas.png")

	// Has to be cstring to interop with Raygui
	file_path := str.clone_to_cstring(os.args[1]) if len(os.args) > 1 else str.clone_to_cstring("default.scrn")
	old_file_path := string(file_path)

	fmt.printfln("%s", file_path)

	screen := screen_from_file(file_path)

	player : Entity 

	// TODO: Move somewhere else?
	player.tail_pos = screen.player_start
	player.cape_pos[0] = screen.player_start
	player.old_position = screen.player_start
	player.position = screen.player_start
	player.velocity = rlb.Vector2 {0, 0}
	player.flip = false
	player.duck = false
	player.airborn = true
	player.tail_color = RED 
	player.tail_accent_color = YELLOW
	player.cape_color = BLUE
	player.player_model_index = 0
	player.edge_run = 0 

	cursor := rlb.Vector2 {0, 0}
	selected_index : i32  = 0
	last_index : i32  = 0
	editor_mode := false

	integer_time: i32 = 0

	// For the load/new screen input box
	show_editor_input := false

	// For the entity input box
	show_editor_input_entity := false

	show_editor_save_msg := false

	// String of the entity data from show_editor_input_entity
	editor_input_entity := str.clone_to_cstring("nil")

	tile_editor := true

	for !rlb.WindowShouldClose() {
		integer_time += 1

		// Coin block animation
		if integer_time % 10 == 0 {
			tile_sprite[COIN_BLOCK_I] += 1 

		}

		// Make switch blocks switch
		if integer_time % 30 == 0 {
			tmp := tile_behavior[SWITCH_BLOCK_I]
			tile_behavior[SWITCH_BLOCK_I] = tile_behavior[SWITCH_BLOCK_I + 1]
			tile_behavior[SWITCH_BLOCK_I + 1] = tmp

			tmp2 := tile_sprite[SWITCH_BLOCK_I]
			tile_sprite[SWITCH_BLOCK_I] = tile_sprite[SWITCH_BLOCK_I + 1]
			tile_sprite[SWITCH_BLOCK_I + 1] = tmp2

			// Reset coin block flash
			tile_sprite[COIN_BLOCK_I] -= 3
		}

		// Open door to next level
		if screen.coins <= 0 {
			tile_sprite[DOOR_BLOCK_I] = 24
			tile_sprite[DOOR_BLOCK_I + 1 ] = 25
		} else {
			tile_sprite[DOOR_BLOCK_I] = 10
			tile_sprite[DOOR_BLOCK_I + 1 ] = 11			
		}

		if rlb.IsGamepadButtonPressed(0, rlb.GamepadButton.MIDDLE_RIGHT) || rlb.IsKeyPressed(rlb.KeyboardKey.GRAVE){
			editor_mode = !editor_mode
		}

		// Editor mode code
		if editor_mode && !show_editor_input && !show_editor_save_msg && !show_editor_input_entity {
			// Quick replace tiles with nothing
			if rlb.IsMouseButtonDown(rlb.MouseButton.RIGHT) {
				if tile_editor {
					// This checks for # of coins, redundant technically 					
					if (screen.tiles[i32(cursor[1])][i32(cursor[0])] == COIN_BLOCK_I) {
						screen.coins -= 1
					}					
					screen.tiles[i32(cursor[1])][i32(cursor[0])] = 0
				} else {

				}
			}

			if tile_editor {
				if rlb.IsKeyPressed(rlb.KeyboardKey.W) {
					last_index = selected_index
					selected_index -= 8
				}
				if rlb.IsKeyPressed(rlb.KeyboardKey.S) {
					last_index = selected_index
					selected_index += 8
				}
				if rlb.IsKeyPressed(rlb.KeyboardKey.A) {
					last_index = selected_index
					selected_index -= 1
				}
				if rlb.IsKeyPressed(rlb.KeyboardKey.D) {
					last_index = selected_index
					selected_index += 1
				}
				if rlb.IsKeyPressed(rlb.KeyboardKey.Q) {
					if selected_index != 0 {
						last_index = selected_index					
						selected_index = 0
					} else {
						selected_index = last_index
					}
				}

				// Replace tile at cursor
				if rlb.IsKeyDown(rlb.KeyboardKey.SPACE) || rlb.IsMouseButtonDown(rlb.MouseButton.LEFT) {
					screen.tiles[i32(cursor[1])][i32(cursor[0])] = u8(selected_index)

					// This checks for # of coins, redundant technically 
					if (selected_index == COIN_BLOCK_I) && (rlb.IsKeyPressed(rlb.KeyboardKey.SPACE) || rlb.IsMouseButtonPressed(rlb.MouseButton.LEFT)) {
						screen.coins += 1
					}
				}		
			}

			// Keyboard editing input
			if rlb.IsKeyPressed(rlb.KeyboardKey.UP) {
				cursor[1] -= 1
			}
			if rlb.IsKeyPressed(rlb.KeyboardKey.DOWN) {
				cursor[1] += 1
			}
			if rlb.IsKeyPressed(rlb.KeyboardKey.LEFT) {
				cursor[0] -= 1
			}
			if rlb.IsKeyPressed(rlb.KeyboardKey.RIGHT) {
				cursor[0] += 1
			}
			if rlb.IsKeyPressed(rlb.KeyboardKey.C) {
				tile_editor = !tile_editor
			}

			// Check if mouse was actually moved for mouse cursor editing
			if rlb.GetMouseDelta() != {0, 0} {
				cursor[1] = mth.floor(f32(rlb.GetMouseY()) / 16.0)
				cursor[0] = mth.floor(f32(rlb.GetMouseX()) / 16.0)			
			}

			cursor[1] = clamp(cursor[1], 0, 27)
			cursor[0] = clamp(cursor[0], 0, 31)

			// Overflow selected_index detection
			if selected_index >= TILE_TYPES {
				selected_index = 0
			} else if selected_index < 0 {
				selected_index = TILE_TYPES-1
			}

			screen.player_start = player.position
		} else if !editor_mode {

			// Handle player stuff
			player_input(&player, integer_time)
			physics_player(&screen, &player.old_position, &player.position, &player.velocity, &player.airborn, &player.edge_run)
			player_state(&player, integer_time)
		}

		rlb.BeginDrawing()

			rlb.BeginTextureMode(render_target)

			rlb.ClearBackground(rlb.BLACK)

			// Draw tiles of a screen
			for i : u8 = 0; i < 28; i += 1 {
				for j : u8 = 0; j < 32; j += 1 {
					if screen.tiles[i][j] != 0 {
						draw_indexed(tile_atlas, i32(tile_sprite[screen.tiles[i][j]]), (i32)(j * 8), (i32)(i * 8), false)
					}
				}
			}

			draw_player(entity_atlas, player, integer_time)

			rlb.EndTextureMode()

			scl_w := f32(768.0 * (2.0 / 3.0)) if editor_mode else 768.0 
			scl_h := f32(672.0 * (2.0 / 3.0)) if editor_mode else 672.0

			rlb.ClearBackground(rlb.BLACK)

			rlb.DrawTexturePro(render_target.texture, {0, 0, f32(render_target.texture.width), -f32(render_target.texture.height)}, 
				{0, 0, scl_w, scl_h}, {0, 0}, 0, rlb.WHITE)

			// Draw editor GUI
			if editor_mode {
				rlb.GuiEnable()

				if tile_editor {
					// Draw tile pallette 
					for i : u8 = 1; i < TILE_TYPES; i += 1 {
						rlb.DrawTexturePro(tile_atlas, {f32((tile_sprite[i] & 7) * 8), f32((tile_sprite[i] &~ 7) >> 3 * 8), 8, 8}, {scl_w + f32((i-1) & 7) * 32, f32((i-1) &~ 7) * 4, 32, 32}, {0, 0}, 0, rlb.WHITE)
					}

					// Highlighting cursor 
					tmp := (i32((selected_index - 1) &~ 7)) * 4

					rlb.DrawRectangleLines(i32(scl_w), 0, 64 * 4, 64 * 4, rlb.RED)

					rlb.DrawRectangleLines((i32((selected_index - 1) & 7) * 32 + i32(scl_w)), tmp - (tmp &~ (31 * 8)), 32, 32, RED)

					if (integer_time & 9) < 5 && selected_index != 0 {
						draw_indexed_pro_scaled(tile_atlas, i32(tile_sprite[selected_index]), i32(cursor[0]) * 16, i32(cursor[1]) * 16, false, 0, {0, 0}, 16)
						rlb.DrawRectangle(i32(cursor[0] * 16 - 1), i32(cursor[1] * 16 - 1), 16, 16, {255, 0, 128, 128})
					}	
				}

				rlb.DrawRectangleLines(i32(cursor[0] * 16 - 1), i32(cursor[1] * 16 - 1), 18, 18, RED if tile_editor else YELLOW)

				rlb.DrawText("UP, DOWN, LEFT, RIGHT / MOUSE - Move cursor", 0, i32(scl_h), 16, rlb.WHITE)	
				rlb.DrawText("WASD - Change tile selection", 0, i32(scl_h) + 16, 16, rlb.WHITE)	
				rlb.DrawText("SPACE / LEFT-CLICK - Replace tile at cursor", 0, i32(scl_h) + 32, 16, rlb.WHITE)	
				rlb.DrawText("X - Save screen", 0, i32(scl_h) + 48, 16, rlb.WHITE)
				rlb.DrawText("Z - Load screen", 0, i32(scl_h) + 64, 16, rlb.WHITE)
				rlb.DrawText("Q / RIGHT-CLICK - Quick erase", 0, i32(scl_h) + 80, 16, rlb.WHITE)	
				rlb.DrawText("C - Switch Entity/Tile mode", 0, i32(scl_h) + 96, 16, rlb.WHITE)					
				rlb.DrawText("` - Exit/Enter editor mode", 0, i32(scl_h) + 114, 16, rlb.WHITE)	

				// Loading screen from file / creating new screen GUI
				if rlb.IsKeyPressed(rlb.KeyboardKey.Z) || show_editor_input {

					show_editor_input = true 
					result := rlb.GuiTextInputBox({f32(rlb.GetRenderWidth() / 2) - 120, f32(rlb.GetRenderHeight() / 2) - 60, 240, 140}, rlb.GuiIconText(rlb.GuiIconName.ICON_FILE_SAVE, "Load screen . . ."), "Load:", "Ok;Cancel", file_path, 255, nil) 
				
					if result == 1 || rlb.IsKeyPressed(rlb.KeyboardKey.ENTER) {
						screen = screen_from_file(file_path)
						old_file_path = string(file_path)
						show_editor_input = false 

						player.tail_pos = screen.player_start
						player.cape_pos[0] = screen.player_start
						player.old_position = screen.player_start
						player.position = screen.player_start
						player.velocity = rlb.Vector2 {0, 0}

					} else if ((result == 0) || (result == 2)) {
						file_path = str.clone_to_cstring(old_file_path)
						show_editor_input = false

						fmt.printfln("%s", old_file_path)
					}

				}

				// Save GUI
				if rlb.IsKeyPressed(rlb.KeyboardKey.X) || show_editor_save_msg {
					show_editor_save_msg = true 

					builder := str.builder_make()

					str.write_string(&builder, "Save file: '")
					str.write_string(&builder, string(file_path))
					str.write_string(&builder, "'")

					s, ok := (str.to_cstring(&builder))

					result := rlb.GuiMessageBox({ f32(rlb.GetRenderWidth() / 2) - 120, f32(rlb.GetRenderHeight() / 2) - 60, 240, 140}, rlb.GuiIconText(rlb.GuiIconName.ICON_EXIT, "Close Window"), s, "Ok;Cancel")

					if result == 1 || rlb.IsKeyPressed(rlb.KeyboardKey.ENTER) {
						show_editor_save_msg = false
						screen_to_file(file_path, screen)
					} else if ((result == 0) || (result == 2)) {
						show_editor_save_msg = false
					}
				}

				// Entity editor GUI
				if (rlb.IsMouseButtonPressed(rlb.MouseButton.LEFT) && !tile_editor) || show_editor_input_entity {
					show_editor_input_entity = true 

					result := rlb.GuiTextInputBox({f32(rlb.GetRenderWidth() / 2) - 120, f32(rlb.GetRenderHeight() / 2) - 60, 240, 140}, rlb.GuiIconText(rlb.GuiIconName.ICON_FILE_SAVE, "Assign Entity . . ."), "Entity:", "Ok;Cancel", editor_input_entity, 255, nil) 
				
					if result == 1 {
						show_editor_input_entity = false

					} else if result == 0 || result == 2 {
						show_editor_input_entity = false;
					}
				}

			} else {
				rlb.GuiDisable()
			}
		rlb.EndDrawing()
	}

}

