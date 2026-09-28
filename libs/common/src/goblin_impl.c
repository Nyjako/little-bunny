/* Single compiled instantiation of GOBLIN's header-only implementations
 * (https://github.com/Nyjako/GOBLIN), so no other translation unit in this
 * project may also define GOBLIN_CSTR_IMPLEMENTATION -- doing so would
 * produce duplicate-symbol errors wherever both end up in the same link
 * (e.g. once M4 links libe621 + libinkbunny + bunny_db together). */
#define GOBLIN_CSTR_IMPLEMENTATION
#include <goblin/cstr.h>
