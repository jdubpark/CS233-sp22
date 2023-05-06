# syscall constants
PRINT_STRING            = 4
PRINT_CHAR              = 11
PRINT_INT               = 1

# memory-mapped I/O
VELOCITY                = 0xffff0010
ANGLE                   = 0xffff0014
ANGLE_CONTROL           = 0xffff0018

BOT_X                   = 0xffff0020
BOT_Y                   = 0xffff0024

OTHER_X                 = 0xffff00a0
OTHER_Y                 = 0xffff00a4

TIMER                   = 0xffff001c
GET_MAP                 = 0xffff2008

REQUEST_PUZZLE          = 0xffff00d0  ## Puzzle
SUBMIT_SOLUTION         = 0xffff00d4  ## Puzzle

BONK_INT_MASK           = 0x1000
BONK_ACK                = 0xffff0060

TIMER_INT_MASK          = 0x8000
TIMER_ACK               = 0xffff006c

REQUEST_PUZZLE_INT_MASK = 0x800       ## Puzzle
REQUEST_PUZZLE_ACK      = 0xffff00d8  ## Puzzle

FALLING_INT_MASK        = 0x200
FALLING_ACK             = 0xffff00f4

STOP_FALLING_INT_MASK   = 0x400
STOP_FALLING_ACK        = 0xffff00f8

POWERWASH_ON            = 0xffff2000
POWERWASH_OFF           = 0xffff2004

GET_WATER_LEVEL         = 0xffff201c

MMIO_STATUS             = 0xffff204c

.data

# Initialize puzzlewrapper of 400 elements with value 0
puzzlewrapper: .byte 0:400

# MAP[40][40] data (size of 40*40*2 = 3200 bytes)
# Each element is a short (half-word, aka. 2 bytes, from 0x00 to 0xFF)
# in format 16b'0DDDDDDDDDDDDDWI:
# - D represents the "dirtiness" of a tile, ranging from 0 - 5000
# - W represents the "walkability" of a tile, is either 0 (non-walkable) or 1 (walkable)
# - I represents the "id" of a tile, is either 0 (a wall) or 1 (a window)
mapdata: .byte 0:3600

# Initialize 1600 elements with value 0
visited: .byte 0:1600 # 40*40 = 1600, one per row-column

# Below variables are single-element with default value of 0

has_puzzle: .word 0

has_bonked: .byte 0

has_timer: .byte 0 # 0 - off // 1 - has timer!

has_movement: .byte 0

has_powerwash: .byte 0

has_falling: .byte 0

has_falling_stop: .byte 0

powerwash_interval: .byte 0

# -- string literals --
.text
main:
    sub $sp, $sp, 4
    sw  $ra, 0($sp)

    # Construct interrupt mask
    li      $t4, 0
    or      $t4, $t4, TIMER_INT_MASK            # enable timer interrupt
    or      $t4, $t4, BONK_INT_MASK             # enable bonk interrupt
    or      $t4, $t4, REQUEST_PUZZLE_INT_MASK   # enable puzzle interrupt
    or      $t4, $t4, 1 # global enable
    mtc0    $t4, $12

    # initial load of map data
    jal     save_map_data

    jal     get_water
    jal     get_water
    jal     get_water
    # jal     get_water
    # jal     get_water
    # jal     get_water

    jal     always_move
    
loop: # Once done, enter an infinite loop so that your bot can be graded by QtSpimbot once 10,000,000 cycles have elapsed
    j loop

#
#
# ===========================================
#                    DFS
# ===========================================
#
#
always_move:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)

    jal     dfs

    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

dfs:
    sub     $sp, $sp, 16
    sw      $ra, 0($sp)
    sw      $s0, 4($sp)
    sw      $s1, 8($sp)
    sw      $s2, 12($sp)

    jal     get_current_xy # $v0: x, $v1: y (in tiles)
    move    $s0, $v0
    move    $s1, $v1
    
    move    $a0, $s0
    move    $a1, $s1
    
    # jal     powerwash_windows
    jal     powerwash_tiles
    jal     find_walkable_directions # returns 0xTRBL (half-word)
    
    beq     $v0, $0, dfs_end # 0xTRBL == 0x0000 (no path to go)
    move    $s2, $v0

    # Direction priority: top > right > bottom > left

    # top (x,y-1)
    and     $t0, $s2, 0x8 # hex for binary 1000
    bne     $t0, $0, dfs_move_top_wrap

    # bottom (x,y+1)
    and     $t0, $s2, 0x2 # hex for binary 0010
    bne     $t0, $0, dfs_move_down_wrap

    # right (x+1,y)
    and     $t0, $s2, 0x4 # hex for binary 0100
    bne     $t0, $0, dfs_move_right_wrap

    # left (x-1,y)
    and     $t0, $s2, 0x1 # hex for binary 0001
    bne     $t0, $0, dfs_move_left_wrap

dfs_end: # all Top, Right, Bottom, Left options are visited, so end DFS
    lw      $ra, 0($sp)
    lw      $s0, 4($sp)
    lw      $s1, 8($sp)
    lw      $s2, 12($sp)
    addi    $sp, $sp, 16
    jr      $ra

dfs_move_top_wrap:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)
    jal     dfs_move_top
    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

dfs_move_top:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)

    jal     face_clock_12 # todo: only turn if get_current_direction != 12 clock
    jal     move_one_tile
    jal     set_current_position_as_visited
    jal     dfs
    # come back
    jal     face_clock_6 # reverse move
    jal     move_one_tile
    jal     dfs

    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

dfs_move_right_wrap:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)
    jal     dfs_move_right
    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

dfs_move_right:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)

    jal     face_clock_3
    jal     move_one_tile
    jal     set_current_position_as_visited
    jal     dfs
    # come back
    jal     face_clock_9
    jal     move_one_tile
    jal     dfs

    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

dfs_move_down_wrap:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)
    jal     dfs_move_down
    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

dfs_move_down:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)

    jal     face_clock_6
    jal     move_one_tile
    jal     set_current_position_as_visited
    jal     dfs
    # come back
    jal     face_clock_12
    jal     move_one_tile
    jal     dfs

    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

dfs_move_left_wrap:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)
    jal     dfs_move_left
    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

dfs_move_left:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)

    jal     face_clock_9
    jal     move_one_tile
    jal     set_current_position_as_visited
    jal     dfs
    # come back
    jal     face_clock_3
    jal     move_one_tile
    jal     dfs

    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

#
#
# ===========================================
#               DFS Map tasks
# ===========================================
#
#
set_current_position_as_visited:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)

    jal     get_current_xy # $v0: x, $v1: y (in tiles)
    la      $t0, visited
    mul     $t1, $v1, 0x28 # y * (40) because row-major access
    add     $t0, $t0, $t1 # add y*40
    add     $t0, $t0, $v0 # add x

    li      $t1, 0xFF
    sb      $t1, 0($t0) # mark (x,y) tile as visited

    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

# Given ($a0,$a1) = (x,y) tile location, return 0xFF if tile is visited, otherwise not 0xF
has_visited_position:
    li      $t0, 39 # [0,39]
    blt     $a0, $0, has_visited_position_out_of_range
    bgt     $a0, $t0, has_visited_position_out_of_range
    blt     $a1, $0, has_visited_position_out_of_range
    bgt     $a1, $t0, has_visited_position_out_of_range

    la      $t0, visited
    mul     $t1, $a1, 0x28 # y * (40) because row-major access
    add     $t0, $t0, $t1 # add y*40
    add     $t0, $t0, $a0 # add x
    lb      $v0, 0($t0)
    and     $v0, $v0, 0x00FF
    jr      $ra

has_visited_position_out_of_range: # return 0xFF (yes) for visited
    li      $t0, 0xFF
    move    $v0, $t0
    jr      $ra

has_visited_current_position:
    sub     $sp, $sp, 12
    sw      $ra, 0($sp)
    sw      $a0, 4($sp)
    sw      $a1, 8($sp)

    jal     get_current_xy # $v0: x, $v1: y (in tiles)
    move    $a0, $v0
    move    $a1, $v1
    jal     has_visited_position

    lw      $ra, 0($sp)
    lw      $a0, 4($sp)
    lw      $a1, 8($sp)
    addi    $sp, $sp, 12
    jr      $ra

#
#
# ===========================================
#                  Map tasks
# ===========================================
#
#
save_map_data: # simply saves current map data to `mapdata`
    la      $t0, mapdata
    la      $t1, GET_MAP
    sb      $t0, 0($t1) # save current map data to address of `mapdata`
    jr      $ra

get_location_data: # returns current map data (16b'0DDDDDDDDDDDDDWI) at tile location ($a0,$a1) = (x,y)
    # Unoptimized (branch) check of range [0,39] for x and y
    # li      $t0, 39 # [0,39]
    # blt     $a0, $0, get_location_data_out_of_range
    # bgt     $a0, $t0, get_location_data_out_of_range
    # blt     $a1, $0, get_location_data_out_of_range
    # bgt     $a1, $t0, get_location_data_out_of_range

    # Less-branch check on range of input —-- wow I'm pretty OP ngl :-)
    li      $t1, 0
    li      $t2, 0
    li      $t4, 10         # 10 instead of -1 to cut going above y=10 (no windows)
    slt     $t1, $t4, $a0   # $t1 = 1 if -1 < $a0, otherwise $t1 = 0 (from li)
    slti    $t2, $a0, 40    # $t2 = 1 if $a0 < 40, otherwise $t2 = 0 (from li)
    and     $t1, $t1, $t2   # $t1 = 1 if -1 < $a0 < 40, otherwise $t1 = 0

    li      $t2, 0
    li      $t3, 0
    slt     $t2, $t4, $a1   # $t2 = 1 if -1 < $a1, otherwise $t2 = 0 (from li)
    slti    $t3, $a1, 40    # $t3 = 1 if $a1 < 40, otherwise $t3 = 0 (from li)
    and     $t2, $t2, $t3   # $t2 = 1 if -1 < $a1 < 40, otherwise $t2 = 0

    and     $t1, $t1, $t2,  # $t1 = 1 if $a0,$a1 \in [0,39], otherwise $t1 = 0
    beq     $t1, $0, get_location_data_out_of_range  # if $t1 = 0 (out-of-range), return 0x8000

    # get location data
    la      $t0, mapdata
    mul     $t1, $a1, 0x50 # y * (40 * 2) because row-major access
    mul     $t2, $a0, 2 # x * 2
    add     $t0, $t0, $t1
    add     $t0, $t0, $t2
    lh      $v0, 0($t0) # load half-word data in the form of 16b'0DDDDDDDDDDDDDWI
    jr      $ra

get_location_data_out_of_range:
    li      $v0, 0x8000 # ie. 1000_0000_0000_0000 (our half-word encoding of out-of-range)
    jr      $ra

get_current_xy: # returns current bot coordinate (x,y) in tiles (size is word = four hex)
    la      $t0, BOT_X
    la      $t1, BOT_Y
    lw      $v0, 0($t0) # in px
    lw      $v1, 0($t1) # in px
    # bot (x,y) is given as the center of 8px by 8px tile
    # sub     $v0, $v0, 4
    # sub     $v1, $v1, 4
    div     $v0, $v0, 0x8
    div     $v1, $v1, 0x8

    jr      $ra

# Given 16b'0DDDDDDDDDDDDDWI (half-word), returns 0x0 or 0x1 where 1 means walkable
tile_walkable:
    # 0x8000 == out-of-range encoding (left-most bit is 1)
    beq     $a0, 0x8000, tile_action_out_of_range

    and     $v0, $a0, 0x3 # WI
    srl     $v0, $v0, 1 # W
    jr      $ra
    
# Given 16b'0DDDDDDDDDDDDDWI (half-word), returns 0x0 or not 0x0 where "not 0x0" means washable AND not clean
# NOTE: this excludes non-windows since they give little points when washed
tile_washable:
    # 0x8000 == out-of-range encoding (left-most bit is 1)
    beq     $a0, 0x8000, tile_action_out_of_range

    andi    $t0, $a0, 0x1   # I (1 is window, 0 is not window)

    li      $t1, 0
    srl     $t2, $a0, 2     # 16b'000DDDDDDDDDDDDD
    slti    $t1, $t2, 1     # $t1 = 1 if $a0 < 1 (0x0 = clean), otherwise $t1 = 0 (from li)
    not     $t1, $t1        # $t1 = 0 is clean (non-washable), 1 is dirty (washable)
    
    and     $v0, $t0, $t1   # is window & is dirty
    jr      $ra

tile_action_out_of_range:
    li      $v0, 0
    jr      $ra

# Given input ($a0,$a1) = (x,y) tile location,
# returns in the format 0xTRBL, where each hex != 0 means walkable & unvisited (for Top, Right, Bottom, Left)
find_walkable_directions:
    sub     $sp, $sp, 52
    sw      $ra, 0($sp)
    sw      $s0, 4($sp)
    sw      $s1, 8($sp)
    sw      $s2, 12($sp)
    sw      $s3, 16($sp)
    sw      $s4, 20($sp)
    sw      $s5, 24($sp)
    sw      $s6, 28($sp)
    sw      $s7, 32($sp)
    sw      $a0, 36($sp)
    sw      $a1, 40($sp)
    sw      $a2, 44($sp)
    sw      $a3, 48($sp)

    move    $s0, $a0 # $s0 = x pos in tile
    move    $s1, $a1 # $s1 = y pos in tile
    
    # top (x,y-1)
    move    $a0, $s0
    move    $a1, $s1
    sub     $a1, 1
    jal     has_visited_position
    move    $s5, $v0
    jal     get_location_data
    move    $a0, $v0
    jal     tile_walkable
    move    $s2, $v0

    # right (x+1,y)
    move    $a0, $s0
    move    $a1, $s1
    addi    $a0, 1
    jal     has_visited_position
    move    $s6, $v0
    jal     get_location_data
    move    $a0, $v0
    jal     tile_walkable
    move    $s3, $v0

    # bottom (x,y+1)
    move    $a0, $s0
    move    $a1, $s1
    addi    $a1, 1
    jal     has_visited_position
    move    $s7, $v0
    jal     get_location_data
    move    $a0, $v0
    jal     tile_walkable
    move    $s4, $v0

    # left (x-1,y)
    move    $a0, $s0
    move    $a1, $s1
    sub     $a0, 1
    jal     has_visited_position
    move    $t6, $v0
    jal     get_location_data
    move    $a0, $v0
    jal     tile_walkable
    move    $t5, $v0

    not     $s5, $s5
    not     $s6, $s6
    not     $s7, $s7
    not     $t6, $t6
    and     $s2, $s2, $s5
    and     $s3, $s3, $s6
    and     $s4, $s4, $s7
    and     $t5, $t5, $t6

    # combine $s2 (top), $s3 (right), $s4 (bottom), $t5 (left) into 0xTRBL
    sll     $v0, $s2, 3
    sll     $s3, $s3, 2
    sll     $s4, $s4, 1
    or      $v0, $v0, $s3
    or      $v0, $v0, $s4
    or      $v0, $v0, $t5
    and     $v0, $v0, 0x0000FFFF

    lw      $ra, 0($sp)
    lw      $s0, 4($sp)
    lw      $s1, 8($sp)
    lw      $s2, 12($sp)
    lw      $s3, 16($sp)
    lw      $s4, 20($sp)
    lw      $s5, 24($sp)
    lw      $s6, 28($sp)
    lw      $s7, 32($sp)
    lw      $a0, 36($sp)
    lw      $a1, 40($sp)
    lw      $a2, 44($sp)
    lw      $a3, 48($sp)
    addi    $sp, $sp, 52
    jr      $ra

#
#
# ===========================================
#                 Move tasks
# ===========================================
#
#
move_one_tile:
    sub     $sp, $sp, 8
    sw      $ra, 0($sp)
    sw      $a0, 4($sp)

    li      $a0, 1
    jal     move_X_tiles

    lw      $ra, 0($sp)
    lw      $a0, 4($sp)
    addi    $sp, $sp, 8
    jr      $ra

move_X_tiles:
    # velocity 10 => 1 tile (8px) after 8000 cycles
    li      $t0, 10
    sw      $t0, VELOCITY

    # Reset timer (otherwise it messes with move_X_tiles_running)
    la      $t0, has_timer
    sb      $0, 0($t0)

    la      $t0, has_movement
    li      $t1, 1
    sb      $t1, 0($t0)

    # Set timer for 8000 * $a0 cycles to pass, where
    # $a0 = # of tiles to walk
    # TODO: account for minor before & after cycle diff (up to +/- 4)
    lb      $t0, TIMER
    li      $t1, 8000
    mul     $t1, $t1, $a0
    add     $t0, $t0, $t1
    sw      $t0, TIMER

move_X_tiles_running:
    lb      $t1, has_movement
    beq     $t1, $0, move_X_tiles_end
    lb      $t0, has_timer
    beq     $t0, $0, move_X_tiles_running

move_X_tiles_end:
    # Pause SPIMBot
    sw      $0, VELOCITY
    la      $t0, has_timer
    sb      $0, 0($t0)
    la      $t0, has_movement
    sb      $0, 0($t0)
    jr      $ra

#
#
# ===========================================
#              Direction tasks
# ===========================================
#
#
get_current_direction:
    la      $t0, ANGLE
    lw      $v0, 0($t0)
    jr      $ra

turn_right: # Relative turn 90 deg
    li      $t0, 90
    sw      $t0, ANGLE
    li      $t0, 0
    sw      $t0, ANGLE_CONTROL
    jr      $ra

turn_left: # Relative turn -90 deg
    li      $t0, -90
    sw      $t0, ANGLE
    li      $t0, 0
    sw      $t0, ANGLE_CONTROL
    jr      $ra

turn_180: # Relative turn 180 deg
    li      $t0, 180
    sw      $t0, ANGLE
    li      $t0, 0
    sw      $t0, ANGLE_CONTROL
    jr      $ra

face_clock_1_5: # 1.5
    li      $t0, 315
    sw      $t0, ANGLE
    li      $t0, 1
    sw      $t0, ANGLE_CONTROL
    jr      $ra

face_clock_3:
    li      $t0, 0
    sw      $t0, ANGLE
    li      $t0, 1
    sw      $t0, ANGLE_CONTROL
    jr      $ra

face_clock_4_5: # 4.5
    li      $t0, 45
    sw      $t0, ANGLE
    li      $t0, 1
    sw      $t0, ANGLE_CONTROL
    jr      $ra

face_clock_6:
    li      $t0, 90
    sw      $t0, ANGLE
    li      $t0, 1
    sw      $t0, ANGLE_CONTROL
    jr      $ra

face_clock_7_5: # 7.5
    li      $t0, 135
    sw      $t0, ANGLE
    li      $t0, 1
    sw      $t0, ANGLE_CONTROL
    jr      $ra

face_clock_9:
    li      $t0, 180
    sw      $t0, ANGLE
    li      $t0, 1
    sw      $t0, ANGLE_CONTROL
    jr      $ra

face_clock_10_5:
    li      $t0, 225
    sw      $t0, ANGLE
    li      $t0, 1
    sw      $t0, ANGLE_CONTROL
    jr      $ra

face_clock_12:
    li      $t0, 270
    sw      $t0, ANGLE
    li      $t0, 1
    sw      $t0, ANGLE_CONTROL
    jr      $ra

#
#
# ===========================================
#                 Wash tasks
# ===========================================
#
#
do_powerwash:
    li      $t0, 0x00030000             # (x, y) with no offset and radius = 3
    sw      $t0, POWERWASH_ON           # 32'b xxxx xxxx RRRR RRRR XXXX XXXX YYYY YYYY

    la      $t0, has_powerwash
    li      $t1, 1
    sb      $t1, 0($t0)

    # Each tile has dirt range of [3000, 5000] with interval of 500.
    # 50 water units are used for every 10 cycles; the water units are
    # spread across all tiles within the radius. Thus, each tile gets
    # 50 / N decrease in dirt, where N = # of tiles covered by the wash.

    # cycles needed (worst case) = ? (maybe 5000/50 * pi * R^2)
    lb      $t2, TIMER
    li      $t3, 80000
    add     $t2, $t2, $t3              # about 63k water units needed per do_powerwash
    sw      $t2, TIMER

running_powerwash:
    lb      $t0, has_timer
    lb      $t1, has_powerwash
    beq     $t1, $0, stop_powerwash
    beq     $t0, $0, running_powerwash

stop_powerwash:
    la      $t0, has_timer
    sb      $0, 0($t0)
    
    la      $t0, has_powerwash
    sb      $0, 0($t0)

    sw      $0, POWERWASH_OFF

    jr      $ra

#
# Unoptimized washing
#
powerwash_tiles:
    # powerwash_interval += 1
    la      $s0, powerwash_interval
    lb      $t1, 0($s0)
    addi    $t1, $t1, 1
    sb      $t1, 0($s0)

    blt     $t1, 4, powerwash_tiles_skip

    sub     $sp, $sp, 8
    sw      $ra, 0($sp)
    sw      $s0, 4($sp)

    # 10k per puzzle, need 63k
    jal     get_water
    jal     get_water
    jal     get_water
    jal     get_water
    jal     get_water
    jal     get_water
    jal     get_water
    jal     get_water
    jal     get_water
    jal     get_water
    jal     get_water
    jal     get_water
    # jal     get_water
    # jal     get_water

    jal     do_powerwash

    sb      $0, 0($s0)      # reset powerwash_interval to 0

    lw      $ra, 0($sp)
    lw      $s0, 4($sp)
    addi    $sp, $sp, 8
    jr      $ra

powerwash_tiles_skip:
    jr      $ra

# Given ($a0,$a1) = (x,y) tile location,
# Find tiles within the radius (manhattan distance) and powerwash if there are X windows.
# Also, solve puzzles (three at a time) if low on water while powerwashing.
# powerwash_windows:
#     sub     $sp, $sp, 4
#     sw      $ra, 0($sp)

#     jal     get_num_windows_within_r_2      # $v0 = # of windows
#     # j powerwash_windows_end
#     # blt     $v0, 3, powerwash_windows_end   # only wash if 3 or mroe windows are washable

#     lw      $ra, 0($sp)
#     addi    $sp, $sp, 4
#     jr      $ra


# powerwash_windows_washing:

#     # 10k per puzzle, need 63k for radius = 2 and max dirt 5000
#     jal     get_water
#     jal     get_water
#     jal     get_water
#     jal     get_water
#     jal     get_water
#     jal     do_powerwash

# powerwash_windows_end:
#     # Save after-wash map data to reflect clean tiles
#     # jal     save_map_data

#     lw      $ra, 0($sp)
#     addi    $sp, $sp, 4
#     jr      $ra

# # Given ($a0,$a1) = (x,y) tile location,
# # Find the number of washable (dirty) windows
# get_num_windows_within_r_2:
#     sub     $sp, $sp, 16
#     sw      $ra, 0($sp)
#     sw      $s0, 4($sp)
#     sw      $s1, 8($sp)
#     sw      $s2, 12($sp)

#     move    $s0, $a0
#     move    $s1, $a1
#     li      $s2, 0          # number of washable windows

#     #
#     # horizontal left (fixed y, subtracting from x)
#     # for radius = 2
#     #
#     sub     $a0, 1
#     jal     get_location_data
#     move    $a0, $v0
#     # jal     tile_washable
#     # add     $s2, $s2, $v0

#     # move    $a0, $s0
#     # sub     $a0, 2
#     # jal     get_location_data
#     # move    $a0, $v0
#     # jal     tile_washable
#     # add     $s2, $s2, $v0

#     # #
#     # # horizontal right (fixed y, adding to x)
#     # # for radius = 2
#     # #
#     # move    $a0, $s0
#     # addi    $a0, 1
#     # jal     get_location_data
#     # move    $a0, $v0
#     # jal     tile_washable
#     # add     $s2, $s2, $v0

#     # move    $a0, $s0
#     # addi    $a0, 2
#     # jal     get_location_data
#     # move    $a0, $v0
#     # jal     tile_washable
#     # add     $s2, $s2, $v0

#     # move    $a0, $s0
#     # #
#     # # vertial top (fixed x, subtrating from x)
#     # # for radius = 2
#     # #
#     # move    $a1, $s1
#     # sub     $a1, 1
#     # jal     get_location_data
#     # move    $a0, $v0
#     # jal     tile_washable
#     # add     $s2, $s2, $v0

#     # move    $a1, $s1
#     # sub     $a1, 2
#     # jal     get_location_data
#     # move    $a0, $v0
#     # jal     tile_washable
#     # add     $s2, $s2, $v0

#     #
#     # vertial bottom (fixed x, adding to x)
#     # for radius = 2
#     #
#     move    $a1, $s1
#     addi    $a1, 1
#     jal     get_location_data
#     move    $a0, $v0
#     jal     tile_washable
#     add     $s2, $s2, $v0

#     move    $a1, $s1
#     addi    $a1, 2
#     jal     get_location_data
#     move    $a0, $v0
#     jal     tile_washable
#     add     $s2, $s2, $v0

#     move    $v0, $s2

#     lw      $ra, 0($sp)
#     lw      $s0, 4($sp)
#     lw      $s1, 8($sp)
#     lw      $s2, 12($sp)
#     addi    $sp, $sp, 16
#     jr      $ra

# # Given ($a0,$a1) = (x,y) tile location,
# # Uses tile_washable
# powerwash_tile_washable_tile:
#     sub     $sp, $sp, 8
#     sw      $ra, 0($sp)
#     sw      $a0, 4($sp)

#     jal     get_location_data   # uses input ($a0,$a1)
#     move    $a0, $v0
#     jal     tile_washable

#     lw      $ra, 0($sp)
#     lw      $a0, 4($sp)
#     addi    $sp, $sp, 8

#
#
# ===========================================
#                Water tasks
# ===========================================
#
#
get_water:
    sub     $sp, $sp, 4
    sw      $ra, 0($sp)

    la      $t0, puzzlewrapper
    la      $t1, REQUEST_PUZZLE
    sb      $t0, 0($t1)
    
    jal     get_water_wait

    lw      $ra, 0($sp)
    addi    $sp, $sp, 4
    jr      $ra

get_water_wait:
    lb      $t0, has_puzzle
    beq     $t0, $0, get_water_wait     # Intermediary wait until puzzle is received

    la      $t0, has_puzzle             # Reset has_puzzle to 0
    sb      $0, 0($t0)

    sub     $sp, $sp, 20
    sw      $ra, 0($sp)
    sw      $a0, 4($sp)
    sw      $a1, 8($sp)
    sw      $a2, 12($sp)
    sw      $a3, 16($sp)

    # Solve puzzle
    la      $t0, puzzlewrapper          # load address of Puzzle struct (puzzlewrapper)
    lw      $a0, 4($t0)                 # board
    lw      $a1, 0($t0)                 # number of rows
    lw      $a2, 8($t0)                 # queen locations
    lw      $a3, 12($t0)                # number of queens

    jal     solve_queens

    la      $t0, puzzlewrapper          # load address of Puzzle struct
    sw      $t0, SUBMIT_SOLUTION        # Submit puzzle solution

    lw      $ra, 0($sp)
    lw      $a0, 4($sp)
    lw      $a1, 8($sp)
    lw      $a2, 12($sp)
    lw      $a3, 16($sp)
    addi    $sp, $sp, 20
    
    jr      $ra


#
#
# ===========================================
#             Helper subroutines
# ===========================================
#
#

# Return 0x0 if $a0 = $0, 0x1 otherwise
is_not_zero:
    beq     $a0, $0, is_not_zero_false
    li      $v0, 0x1
    jr      $ra

is_not_zero_false:
    move    $v0, $0
    jr      $ra
# -----------------------------------------------------------------------
# form_half_word - given 0xA, 0xB, 0xC, 0xD, return 0xABCD
# $a0 - 0x*******A
# $a1 - 0x*******B
# $a2 - 0x*******C
# $a3 = 0x*******D
# returns 0xABCD (= 0x0000ABCD)
# -----------------------------------------------------------------------
form_half_word:
    and     $a0, $a0, 0xF
    sll     $a0, $a0, 12
    ori     $v0, $a0, 0     # $v0  = 0x0000A000
    and     $a1, $a1, 0xF
    sll     $a1, $a1, 8
    or      $v0, $v0, $a1   # $v0 |= 0x00000B00
    and     $a2, $a2, 0xF
    sll     $a2, $a2, 4
    or      $v0, $v0, $a2   # $v0 |= 0x000000C0
    and     $a3, $a3, 0xF
    or      $v0, $v0, $a3   # $v0 |= 0x0000000D
    jr      $ra             #      = 0x0000ABCD

#
#
# ===========================================
#                 Interrupts
# ===========================================
#
#
.kdata
chunkIH:    .space 40
non_intrpt_str:    .asciiz "Non-interrupt exception\n"
unhandled_str:    .asciiz "Unhandled interrupt type\n"
.ktext 0x80000180
interrupt_handler:
.set noat
    move    $k1, $at        # Save $at
                            # NOTE: Don't touch $k1 or else you destroy $at!
.set at
    la      $k0, chunkIH
    sw      $a0, 0($k0)        # Get some free registers
    sw      $v0, 4($k0)        # by storing them to a global variable
    sw      $t0, 8($k0)
    sw      $t1, 12($k0)
    sw      $t2, 16($k0)
    sw      $t3, 20($k0)
    sw      $t4, 24($k0)
    sw      $t5, 28($k0)

    # Save coprocessor1 registers!
    # If you don't do this and you decide to use division or multiplication
    #   in your main code, and interrupt handler code, you get WEIRD bugs.
    mfhi    $t0
    sw      $t0, 32($k0)
    mflo    $t0
    sw      $t0, 36($k0)

    mfc0    $k0, $13                # Get Cause register
    srl     $a0, $k0, 2
    and     $a0, $a0, 0xf           # ExcCode field
    bne     $a0, 0, non_intrpt

interrupt_dispatch:                 # Interrupt:
    mfc0    $k0, $13                # Get Cause register, again
    beq     $k0, 0, done            # handled all outstanding interrupts

    and     $a0, $k0, BONK_INT_MASK     # is there a bonk interrupt?
    bne     $a0, 0, bonk_interrupt

    and     $a0, $k0, TIMER_INT_MASK    # is there a timer interrupt?
    bne     $a0, 0, timer_interrupt

    and     $a0, $k0, REQUEST_PUZZLE_INT_MASK
    bne     $a0, 0, request_puzzle_interrupt

    and     $a0, $k0, FALLING_INT_MASK
    bne     $a0, 0, falling_interrupt

    and     $a0, $k0, STOP_FALLING_INT_MASK
    bne     $a0, 0, stop_falling_interrupt

    li      $v0, PRINT_STRING       # Unhandled interrupt types
    la      $a0, unhandled_str
    syscall
    j       done

bonk_interrupt:
    sw      $0, BONK_ACK
    la      $t0, has_bonked
    li      $t1, 1
    sb      $t1, 0($t0)
    #Fill in your bonk handler code here
    j       interrupt_dispatch      # see if other interrupts are waiting

timer_interrupt:
    sw      $0, TIMER_ACK
    la      $t0, has_timer
    li      $t1, 1                  
    sb      $t1, 0($t0)             # has_timer = 1
    j        interrupt_dispatch     # see if other interrupts are waiting

request_puzzle_interrupt:
    sw      $0, REQUEST_PUZZLE_ACK
    la      $t0, has_puzzle
    li      $t1, 1
    sb      $t1, 0($t0)
    j       interrupt_dispatch

falling_interrupt:
    sw      $0, FALLING_ACK
    la      $t0, has_falling
    li      $t1, 1
    sb      $t1, 0($t0)
    la      $t0, has_falling_stop
    li      $t1, 0
    sb      $t1, 0($t0)
    j       interrupt_dispatch

stop_falling_interrupt:
    sw      $0, STOP_FALLING_ACK
    la      $t0, has_falling
    li      $t1, 0
    sb      $t1, 0($t0)
    la      $t0, has_falling_stop
    li      $t1, 1
    sb      $t1, 0($t0)
    j       interrupt_dispatch

non_intrpt:                         # was some non-interrupt
    li      $v0, PRINT_STRING
    la      $a0, non_intrpt_str
    syscall                         # print out an error message
    # fall through to done

done:
    la      $k0, chunkIH

    # Restore coprocessor1 registers!
    # If you don't do this and you decide to use division or multiplication
    #   in your main code, and interrupt handler code, you get WEIRD bugs.
    lw      $t0, 32($k0)
    mthi    $t0
    lw      $t0, 36($k0)
    mtlo    $t0

    lw      $a0, 0($k0)             # Restore saved registers
    lw      $v0, 4($k0)
    lw      $t0, 8($k0)
    lw      $t1, 12($k0)
    lw      $t2, 16($k0)
    lw      $t3, 20($k0)
    lw      $t4, 24($k0)
    lw      $t5, 28($k0)

.set noat
    move    $at, $k1        # Restore $at
.set at
    eret


#
#
# ===========================================
#               Puzzle solver
# ===========================================
#

.text
.globl is_attacked
is_attacked:
    li $t0,0 #counter i=0
    li $t1,0 #counter j=0
    
    move $t2,$a1 #counter N
    j forloopvertical
    
forloopvertical:
    bge $t0,$t2,forloophorizontal  # if i >= n move on to next for loop
    bne $t0,$a2,verticalcheck  #checking i != row, if i != row move onto next check
    add $t0,$t0,1  # incrementing i = i+1
    j forloopvertical # jump back to for
    
verticalcheck:
    mul $t3, $t0, 4     # convert index to offset address for row
    add $t4, $a0, $t3   # add offset to base address of board
    lw  $t5, 0($t4)     # load address of board[row(i)] in $t5, $t5 is pointing to the beginning of the char*
    add $t6, $t5, $a3   # add offset to base address of board[row(i)]
    lb  $t7, 0($t6)     # load board[row(i)][col] in $t7
    beq $t7,1,return1   # if board[i][col] == 1 return 1
    add $t0,$t0,1       # increment i = i+1
    j forloopvertical   # jump to for loop

forloophorizontal:
    bge $t1,$t2,resetiandjleft  # if j >= n move on to next for loop
    bne $t1,$a3,horizontalcheck  #checking j != col, if j != col move onto next check
    add $t1,$t1,1  # incrementing j = j+1
    j forloophorizontal # jump back to for
    
horizontalcheck:
    mul $t3, $a2, 4     # convert index to offset address for row
    add $t4, $a0, $t3   # add offset to base address of board
    lw  $t5, 0($t4)     # load address of board[row] in $t5, $t5 is pointing to the beginning of the char*
    add $t6, $t5, $t1   # add offset to base address of board[row]
    lb  $t7, 0($t6)     # load board[row][col(j)] in $t7
    beq $t7,1,return1   # if board[row][j] == 1 return 1
    add $t1,$t1,1       # increment j = j+1
    j forloophorizontal   # jump to for loop

resetiandjleft:
    li $t0,0    # i = 0
    li $t1,0    # j = 0
    j forleftdiagonal

forleftdiagonal:
    bge $t0,$t2,resetiandjright #for int i = 0; i <n; i++
    beq $t0,$a2,incrementileft # (i != row)
    
    sub $t3,$t0,$a2
    add $t1,$t3,$a3 #int j = (i-row) + col
    
    blt $t1,0,incrementileft # j>=0
    bge $t1,$t2,incrementileft # j < n
    
    mul $t3, $t0, 4     # convert index to offset address for row
    add $t4, $a0, $t3   # add offset to base address of board
    lw  $t5, 0($t4)     # load address of board[row] in $t5, $t5 is pointing to the beginning of the char*
    add $t6, $t5, $t1   # add offset to base address of board[row]
    lb  $t7, 0($t6)     # load board[row][col(j)] in $t7
    beq $t7,1,return1   # if board[row][j] == 1 return 1
    
    add $t0,$t0,1
    j forleftdiagonal

incrementileft:
    add $t0,$t0,1
    j forleftdiagonal
    

resetiandjright:
    li $t0,0
    li $t1,0
    j forrightdiagonal

forrightdiagonal:
    bge $t0,$t2,return0 #for int i = 0; i <n; i++
    beq $t0,$a2,incrementiright # (i != row)
    
    sub $t3,$a2,$t0
    add $t1,$t3,$a3 #int j = (row-i) + col
    
    blt $t1,0,incrementiright # j>=0
    bge $t1,$t2,incrementiright # j < n
    
    mul $t3, $t0, 4     # convert index to offset address for row
    add $t4, $a0, $t3   # add offset to base address of board
    lw  $t5, 0($t4)     # load address of board[row] in $t5, $t5 is pointing to the beginning of the char*
    add $t6, $t5, $t1   # add offset to base address of board[row]
    lb  $t7, 0($t6)     # load board[row][col(j)] in $t7
    beq $t7,1,return1   # if board[row][j] == 1 return 1
    
    add $t0,$t0,1
    j forrightdiagonal

incrementiright:
    add $t0,$t0,1
    j forrightdiagonal
    
return1:
    li $v0,1            # output 1
    jr $ra              # return

return0:
    li $v0,0            # output 0
    jr $ra              # return

.globl place_queen_step
place_queen_step:
    li      $v0, 1
    beq     $a3, $0, pqs_return     # if (queens_left == 0)

pqs_prologue: 
    sub     $sp, $sp, 36 
    sw      $s0, 0($sp)
    sw      $s1, 4($sp)
    sw      $s2, 8($sp)
    sw      $s3, 12($sp)
    sw      $s4, 16($sp)
    sw      $s5, 20($sp)
    sw      $s6, 24($sp)
    sw      $s7, 28($sp)
    sw      $ra, 32($sp)

    move    $s0, $a0                # $s0 = board
    move    $s1, $a1                # $s1 = n
    move    $s2, $a2                # $s2 = pos
    move    $s3, $a3                # $s3 = queens_left

    move    $s4, $a2                # $s4 = i = pos

pqs_for:
    mul     $t0, $s1, $s1           # $t0 = n * n
    bge     $s4, $t0, pqs_for_end   # break out of loop if !(i < n * n)

    div     $s5, $s4, $s1           # $s5 = row = i / n
    rem     $s6, $s4, $s1           # $s6 = col = i % n

    sll     $s7, $s5, 2             # $s7 = row * 4
    add     $s7, $s7, $s0           # $s7 = &board[row] = board + row * 4
    lw      $s7, 0($s7)             # $s7 = board[row]

    add     $s7, $s7, $s6           # $s7 = &board[row][col] = board[row] + col
    lb      $t1, 0($s7)             # $t1 = board[row][col]

    bne     $t1, $0, pqs_for_inc    # skip if !(board[row][col] == 0)

    move    $a0, $s0                # board
    move    $a1, $s1                # n
    move    $a2, $s5                # row
    move    $a3, $s6                # col
    jal     is_attacked             # call is_attacked(board, n, row, col)

    bne     $v0, $0, pqs_for_inc    # skip if !(is_attacked(board, n, row, col) == 0)

    li      $t0, 1
    sb      $t0, 0($s7)             # board[row][col] = 1

    move    $a0, $s0                # board
    move    $a1, $s1                # n
    add     $a2, $s2, 1             # pos + 1
    sub     $a3, $s3, 1             # queens_left - 1
    jal     place_queen_step        # call place_queen_step(board, n, pos + 1, queens_left - 1)

    beq     $v0, $0, pqs_reset_square       # skip return if !(place_queen_step(board, n, pos + 1, queens_left - 1) == 0)

    li      $v0, 1
    j       pqs_epilogue            # return 1

pqs_reset_square:
    sb      $0, 0($s7)              # board[row][col] = 0

pqs_for_inc:
    add     $s4, $s4, 1             # ++i
    j       pqs_for

pqs_for_end:
    move    $v0, $0                  # return 0

pqs_epilogue:
    lw      $s0, 0($sp)
    lw      $s1, 4($sp)
    lw      $s2, 8($sp)
    lw      $s3, 12($sp)
    lw      $s4, 16($sp)
    lw      $s5, 20($sp)
    lw      $s6, 24($sp)
    lw      $s7, 28($sp)
    lw      $ra, 32($sp)
    add     $sp, $sp, 36 

pqs_return:
    jr      $ra

.globl solve_queens
solve_queens:
sq_prologue:
    sub     $sp, $sp, 20
    sw      $s0, 0($sp)
    sw      $s1, 4($sp)
    sw      $s2, 8($sp)
    sw      $s3, 12($sp)
    sw      $ra, 16($sp)

    move    $s0, $a0
    move    $s1, $a1
    move    $s2, $a2
    move    $s3, $a3

    li      $t0, 0      # $t0 is i

sq_for_i:
    beq     $t0, $s1, sq_end_for_i
    li      $t1, 0      # $t1 is j

sq_for_j:
    beq     $t1, $s1, sq_end_for_j

    sll     $t3, $t0, 2             # $t3 = i * 4
    add     $t3, $t3, $s0           # $t3 = &board[i] = board + i * 4
    lw      $t3, 0($t3)             # $t3 = board[i]

    add     $t3, $t3, $t1           # $t3 = &board[i][j] = board[i] + j
    sb      $0, 0($t3)              # board[i][j] = 0

    add     $t1, $t1, 1     # ++j
    j       sq_for_j

sq_end_for_j:
    add     $t0, $t0, 1     # ++i
    j       sq_for_i

sq_end_for_i:
sq_ll_setup:
    move    $t5, $a2        # $t5 is curr

sq_ll_for:
    beq     $t5, $0, sq_ll_end
    
    lw      $t6, 0($t5)         # $t6 = curr->pos
    div     $t0, $t6, $s1       # $t0 = row = pos / n
    rem     $t1, $t6, $s1       # $t1 = col = pos % n
    
    sll     $t3, $t0, 2             # $t3 = row * 4
    add     $t3, $t3, $s0           # $t3 = &board[row] = board + row * 4
    lw      $t3, 0($t3)             # $t3 = board[row]

    add     $t3, $t3, $t1           # $t3 = &board[row][col] = board[row] + col
    li      $t7, 1
    sb      $t7, 0($t3)             # board[row][col] = 1

    lw      $t5, 4($t5)             # curr = curr->next

    j       sq_ll_for

sq_ll_end:
    move    $a2, $0
    jal     place_queen_step        # call place_queen_step(sol_board, n, 0, queens_to_place)

sq_epilogue:
    lw      $s0, 0($sp)
    lw      $s1, 4($sp)
    lw      $s2, 8($sp)
    lw      $s3, 12($sp)
    lw      $ra, 16($sp)

    add     $sp, $sp, 20
    jr      $ra