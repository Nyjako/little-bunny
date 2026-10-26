/* Single compiled instantiation of GOBLIN's header-only implementations
 * (https://github.com/Nyjako/GOBLIN), so no other translation unit in this
 * project may also define these *_IMPLEMENTATION macros -- doing so would
 * produce duplicate-symbol errors wherever both end up in the same link
 * (e.g. bunny_core links libe621 + libinkbunny + bunny_db + bunny_common
 * together). */
#define GOBLIN_CSTR_IMPLEMENTATION
#include <goblin/cstr.h>

#define GOBLIN_APPDIR_IMPLEMENTATION
#include <goblin/appdirs.h>

#define GOBLIN_HIGH_RES_TIMER_IMPLEMENTATION
#include <goblin/high_res_timer.h>

#define GOBLIN_FILEIO_IMPLEMENTATION
#include <goblin/fileio.h>

#define GOBLIN_ENV_IMPLEMENTATION
#include <goblin/env.h>
