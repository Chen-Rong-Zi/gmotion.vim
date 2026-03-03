" Vim global plugin for correcting typing mistakes
" Last Change:	2024 Dec 30
" Maintainer:	Chen RongZi <231220088@smail.nju.edu.cn>
" License:	This file is placed in the public domain.

if !has('vim9script')
    finish
endif
vim9script noclear

if exists("g:loaded_gmotion")
    finish
endif

const MAX_TOKENS = 100
const MAX_CHARS = 10000


if exists("g:gmotion_highligh_group")
    try
        silent! exe 'highlight ' .. g:gmotion_highligh_group
    catch /E411:.*/
        echom "Gmotion: " .. "can not found highlight group '" .. g:Gmotion .. "', try 'MatchParen'"
        finish
    endtry
else
    g:gmotion_highligh_group = 'MatchParen'
endif

if exists("g:gmotion_pair")
    if typename(g:gmotion_pair) !=# 'list<list<string>>'
        echom "Gmotion: " .. "g:gmotion_pair must be a value typed 'list<list<string>>'"
        finish
    endif

    for pair in g:gmotion_pair
        if len(pair) !=# 2
            echom "Gmotion: " .. "element in g:gmotion_pair must be two-length list"
            finish
        endif
    endfor
else
    const g:gmotion_pair = [
        ['(', ')'],
        ['[', ']'],
        ['{', '}'],
        ['`', '`'],
        ['"', '"'],
        ["'", "'"],
    ]
endif

g:loaded_gmotion = 1
const special_pair = g:gmotion_pair->copy()->filter((idx: number, match: list<string>) => match[0] ==# match[1])
const schar = special_pair->copy()->map((i: number, v: list<string>) => v[0])
const lpart = g:gmotion_pair->copy()->map((i: number, v: list<string>) => v[0])
const rpart = g:gmotion_pair->copy()->map((i: number, v: list<string>) => v[1])
const chars = lpart + rpart

const InPair  = (lst:  list<string>): bool => g:gmotion_pair->index(lst) !=# -1
const InChar  = (char: string):       bool => chars->index(char)  !=# -1
const InRpart = (char: string):       bool => rpart->index(char)  !=# -1
const InLpart = (char: string):       bool => lpart->index(char)  !=# -1
const InSchar = (char: string):       bool => schar->index(char)  !=# -1

const TheOtherPair = g:gmotion_pair->copy()->map((idx: number, pair: list<string>) => {
        return [[pair[0], pair], [pair[1], pair]]
    })->reduce((pre: dict<list<any>>, curr: list<list<any>>) => {
        pre[curr[0][0]] = curr[0][1]
        pre[curr[1][0]] = curr[1][1]
        return pre
    }, {})

abstract class Result
    var inner_value: any
    var IsFailure: bool
endclass

class Success extends Result
    def new(value: any)
        this.inner_value = value
        this.IsFailure = false
    enddef
endclass

class Failure extends Result
    def new(value: any)
        this.inner_value = value
        this.IsFailure = true
    enddef
endclass

class Position
    public var row: number
    public var bcol: number
    public var content: string
    public var len: number
    public var is_first_line: bool
    def new(content: string, row: number, col: number)
        this.is_first_line = false
        this.content = content
        this.len = len(this.content)
        this.row = row
        this.bcol = col
    enddef
endclass


def EqualMe(me: Position, other: Position): bool
    return me.row ==# other.row && me.bcol ==# other.bcol
enddef
def BeforeMe(me: Position, other: Position): bool
    if EqualMe(me, other)
        return false
    else
        return !AfterMe(me, other)
    endif
enddef
def AfterMe(me: Position, other: Position): bool
    if other.row ># me.row
        return true
    elseif other.row ==# me.row && other.bcol > me.bcol
        return true
    else
        return false
    endif
enddef
def Distance(me: Position, anchor: Position): number
    const big_bit   = abs(anchor.row - me.row)
    const small_bit = abs(anchor.bcol - me.bcol)
    return big_bit * 1000 + small_bit
enddef

class MatchPair
    public final left:  Position
    public final right: Position
    public var   hl_id: Result
    public var winid: number

    def new(left: Position, right: Position)
        this.left  = left
        this.right = right
        this.hl_id = Failure.new("null hl_id")
        this.winid = 0
    enddef
    def InMe(pos: Position): bool
        if BeforeMe(pos, this.right) || AfterMe(pos, this.left)
            return false
        else
            return true
        endif
    enddef
    def Distance(anchor: Position): number
        if this.left.row !=# anchor.row
            return abs(this.right.bcol - anchor.bcol)
        elseif this.right.row !=# anchor.row
            return abs(this.left.bcol - anchor.bcol)
        else
            return min([
                abs(this.left.bcol - anchor.bcol),
                abs(this.right.bcol - anchor.bcol)
            ])
        endif
    enddef
    def HighLight()
        this.hl_id = Success.new(matchaddpos(g:gmotion_highligh_group, [[this.left.row,  this.left.bcol,  this.left.len], [this.right.row, this.right.bcol, this.right.len]]))
        this.winid = win_getid()
    enddef
    def HighLightClear()
        if win_id2tabwin(this.winid) ==# [0, 0]
            return
        endif
        if this.hl_id.IsFailure
            return
        endif
        matchdelete(this.hl_id.inner_value, this.winid)
        this.hl_id = Failure.new("null hl_id")
    enddef

endclass


class Stack
    public var content: list<Position>
    def new()
        this.content = []
    enddef
    def Empty(): bool
        return this.content->len() ==# 0
    enddef
    def Top(): Result
        if len(this.content) !=# 0
            return Success.new(this.content[0])
        else
            return Failure.new("长度为0，不能出栈")
        endif
    enddef
    def Last(): Result
        if len(this.content) !=# 0
            return Success.new(this.content[-1])
        else
            return Failure.new("长度为0，不能出栈")
        endif
    enddef
    def Pop(): Result
        if len(this.content) ==# 0
            return Failure.new("Stack 没有任何元素")
        else
            return Success.new(this.content->remove(0))
        endif
    enddef

    def Push(value: Position)
        this.content->insert(value, 0)
    enddef

endclass


class FrontStack extends Stack
    def PushLeft(pos: Position): list<MatchPair>
        this.Push(pos)
        return []
    enddef

    def PushRight(r_pos: Position): list<MatchPair>
        const top: Result = this.Top()
        if top.IsFailure ==# true
            return []
        endif

        const l_pos: Position = top.inner_value
        if InPair([l_pos.content, r_pos.content])
            this.Pop()
            return [MatchPair.new(l_pos, r_pos)]
        else
            return []
        endif
    enddef
endclass

class BackStack extends Stack
    def PushLeft(l_pos: Position): list<MatchPair>
        const top: Result = this.Top()
        if top.IsFailure ==# true
            return []
        endif

        const r_pos: Position = top.inner_value
        if InPair([l_pos.content, r_pos.content])
            this.Pop()
            return [MatchPair.new(l_pos, r_pos)]
        else
            return []
        endif
    enddef

    def PushRight(pos: Position): list<MatchPair>
        this.Push(pos)
        return []
    enddef
endclass

class MatchPairStack
    public final front:         FrontStack
    public final front_special: FrontStack
    public final back:          BackStack
    public final back_special:  BackStack

    def new()
        this.back          = BackStack.new()
        this.back_special  = BackStack.new()
        this.front         = FrontStack.new()
        this.front_special = FrontStack.new()
    enddef

    def PushFront(pos: Position): list<MatchPair>
        if InSchar(pos.content)
            const top: Result = this.front_special.Top()
            if top.IsFailure ==# true
                return this.front_special.PushLeft(pos)
            endif

            const l_pos: Position = top.inner_value
            if InPair([l_pos.content, pos.content])
                this.front_special.Pop()
                return [MatchPair.new(l_pos, pos)]
            else
                return this.front_special.PushLeft(pos)
            endif
        elseif InLpart(pos.content)
            this.front.PushLeft(pos)
            return []
        else
            return this.front.PushRight(pos)
        endif
    enddef

    def PushBack(pos: Position): list<MatchPair>
        if InSchar(pos.content)
            const top: Result = this.back_special.Top()
            if top.IsFailure ==# true
                return this.back_special.PushLeft(pos)
            endif

            const r_pos: Position = top.inner_value
            if InPair([pos.content, r_pos.content])
                this.back_special.Pop()
                return [MatchPair.new(pos, r_pos)]
            else
                return this.back_special.PushLeft(pos)
            endif
        elseif InLpart(pos.content)
            return this.back.PushLeft(pos)
        else
            return this.back.PushRight(pos)
        endif
    enddef

endclass

def Enumerate(lst: list<any>): list<any>
    return lst->copy()->map((idx, c) => [c, idx])
enddef

def Nth_on_condition(lst: list<any>, condition: any): Result
    for [ele, i] in Enumerate(lst)
        if condition(ele)
            return Success.new(i)
        endif
    endfor
    return Failure.new("not found in " .. string(lst))
enddef

def Tokenize(line: string, row: number): list<any>
    const characters = line->split('\zs')
    var result: list<any>  = []
    var bcol: number = 0
    for [char, idx] in Enumerate(characters)
        const pos: Position = Position.new(char, row, bcol + 1)
        if !InChar(char)
        else
            result += [pos]
        endif
        bcol += len(char)
    endfor
    return result
enddef

def ExtractPairToken(line: string, content: list<string>, row: number): list<Position>
    const characters = line->split('\zs')
    var result: list<Position>  = []
    var bcol: number = 0
    for [char, idx] in Enumerate(characters)
        if content->index(char) !=# -1
            const pos: Position = Position.new(char, row, bcol + 1)
            result += [pos]
        endif
        bcol += len(char)
    endfor
    return result
enddef

def OnlyNthPosition(tokens: list<Position>, index: number): list<Position>
    if len(tokens) ==# 0
        return []
    else
        return tokens->copy()->filter((i: number, pos: Position) => pos.content ==# tokens[index].content)
    endif
enddef

def FParseFirstLine(tokens: list<any>, row: number): list<list<Position>>
    var front: list<any> = tokens
    var back:  list<any> = []
    var front_end = 0
    var back_end  = -1
    if front ==# []
        return []
    endif
    while (0 != front->len()) && (!InLpart(front[0].content))
        back->insert(front->remove(0), 0)
    endwhile

    if len(front) >=# 2
        var last_tk = front[0]
        var lpair = TheOtherPair[last_tk.content]
        var i = 1
        while i < len(front)
            if front[i].content ==# lpair[1]
                front = front[2 : ]
            else
                last_tk = front[i]
                lpair = TheOtherPair[last_tk.content]
            endif
            i  += 1
        endwhile
    endif

    if len(back) >=# 2
        var last_tk = back[-1]
        var lpair = TheOtherPair[last_tk.content]
        var i = -2
        while abs(i) < len(back)
            if back[i].content ==# lpair[0]
                back = back[ : -3]
            else
                last_tk = back[i]
                lpair = TheOtherPair[last_tk.content]
            endif
            i  -= 1
        endwhile
    endif

    return [
        OnlyNthPosition(back,  back_end),
        OnlyNthPosition(front, front_end)
    ]
enddef

def ParseLineRange(row: number): Result # list<number>
    var thisline = getline(row)
    var thisline_tokens = Tokenize(thisline, row)
    var total_chars  = len(thisline)
    var total_tokens = len(thisline_tokens)
    const MAX_ROWS = line('$')
    const back_front = FParseFirstLine(thisline_tokens, row)
    var front_path = row
    var back_path  = row
    var level = 1
    var left_end = front_path
    var right_end = back_path
    if [[], []] ==# back_front
        return Success.new([row, row])
    elseif [] ==# back_front
        # return Success.new([-1, -1])
        return Failure.new('Exceed Max Chars:' .. string(total_chars) .. "  Max Tokens: " .. string(total_tokens))
    endif
    const [back, front] = back_front

    if len(front) ==# 0
        right_end = front_path
    else
        const lpair = TheOtherPair[front[0].content]
        while front_path <# MAX_ROWS
            front_path += 1
            thisline = getline(front_path)
            total_chars += len(thisline)
            const pairtokens = ExtractPairToken(thisline, lpair, front_path)
            total_tokens += len(pairtokens)
            if total_chars >=# MAX_CHARS || total_tokens >=# MAX_TOKENS
                return Failure.new('Exceed Max Chars:' .. string(total_chars) .. "  Max Tokens: " .. string(total_tokens))
            endif
            for tk in pairtokens
                if tk.content ==# lpair[1]
                    level -= 1
                    if level ==# 0
                        break
                    endif
                elseif tk.content ==# lpair[0]
                    level += 1
                endif
            endfor
            if level ==# 0
                right_end = front_path
                break
            endif
        endwhile
    endif

    if len(back) ==# 0
        left_end = back_path
    else
        const rpair = TheOtherPair[back[-1].content]
        while back_path > 1
            back_path -= 1
            thisline = getline(back_path)
            total_chars += len(thisline)
            total_tokens += len(thisline)
            const pairtokens = ExtractPairToken(thisline, rpair, back_path)
            total_tokens += len(pairtokens)
            if total_chars >=# MAX_CHARS || total_tokens >=# MAX_TOKENS
                return Failure.new('Exceed Max Chars:' .. string(total_chars) .. "  Max Tokens: " .. string(total_tokens))
            endif
            for tk in pairtokens
                if tk.content ==# rpair[0]
                    level -= 1
                    if level ==# 0
                        break
                    endif
                elseif tk.content ==# rpair[1]
                    level += 1
                endif
            endfor
            if level ==# 0
                left_end = back_path
                break
            endif
        endwhile
    endif
    return Success.new([left_end, right_end])
enddef


def From_capture(format: string, line: string, base_row: number): Position
    const regex     = matchstr(line, format)
    const row_index = substitute(regex, format, '\1', '')
    const col_index = substitute(regex, format, '\2', '')
    const row       = str2nr(row_index) + base_row
    const col       = str2nr(col_index) + 1
    return Position.new(
        line[-2 : -2],
        row,
        col
    )
enddef

def From_pattern_capture(format: string, lines: list<string>, base_row: number): MatchPair
    const left_pos  = From_capture(format, lines[1][23 : ], base_row)
    const right_pos = From_capture(format, lines[2][24 : ], base_row)
    return MatchPair.new(
        left_pos,
        right_pos
    )
enddef

def F_parse(lines: list<string>, base_row: number): list<MatchPair>
    const format = 'start: (\(\d\+\), \(\d\+\)), end: (\(\d\+\), \(\d\+\)).*'
    final matches: list<MatchPair> = []
    const length = lines->len()
    var base = 0
    while true
        if base >=# length
            break
        endif
        const m = From_pattern_capture(format, lines[base : base + 2], base_row)
        matches->extend([m])
        base += 3
    endwhile
    return matches
enddef

def From_tree_sitter(output: string, base: number): list<MatchPair>
    const lines = output->split("\n")
    const length = len(lines)
    return F_parse(lines[ : -(length % 3 + 1)], base)
enddef


def ParseFirstLine(tokens: list<any>, row: number): list<any>
    var front: list<any> = tokens
    var back:  list<any> = []
    while (0 != front->len()) && (!InLpart(front[0].content))
        back->insert(front->remove(0), 0)
    endwhile

    var stack = MatchPairStack.new()

    var front_result = front->map((_, front_ele) => {
        front_ele.is_first_line = true
        const result = stack.PushFront(front_ele)
        if result ==# [] && (!InLpart(front_ele.content))
            back->insert(front_ele, 0)
        endif
        return result
    })->reduce((pre, curr) => pre + curr, [])

    var back_result = back->map((_, back_ele) => {
        back_ele.is_first_line = true
        return stack.PushBack(back_ele)
    })->reduce((pre, curr) => pre + curr, [])

    return [back_result + front_result, stack]
enddef

def ParseFrontLine(content: string, row: number): list<any>
    return Tokenize(content, row)
enddef

def ParseBackLine(content: string, row: number): list<any>
    return Tokenize(content, row)->reverse()
enddef

def Max(lst: list<MatchPair>, cursor: Position): MatchPair
    var min_dis: number = lst[0].Distance(cursor)
    var min: MatchPair = lst[0]
    for i in lst[1 : ]
        var temp: number = i.Distance(cursor)
        if temp < min_dis
            min_dis = temp
            min = i
        endif
    endfor
    return min
enddef

class PairCache
    public var bufid: number
    public var cache: dict<list<MatchPair>>
    public var stamp: float
    public var first_row:  number = 1
    public var second_row: number = 1

    def new(bufid: number)
        this.cache = {}
        this.bufid = bufid
        this.stamp = reltimefloat(reltime())
    enddef

    def Update(row0: number, row1: number)
        const match_lst: list<MatchPair> = ParseLines(row0, row1)

        this.cache = []
        for row in range(row0, row1)
            this.cache[row] = []
        endfor
        for match in match_lst
            this.cache[match.right.row]->insert(match, 0)
            this.cache[match.left.row]->insert(match,  0)
        endfor
    enddef


    def UpdateOnNeedHelper(row: number): Result
        const MAX_ROWS = line('$')
        var thisline = getline(row)
        var total_chars = len(thisline)
        var thisline_tokens = Tokenize(thisline, row)
        var total_tokens = len(thisline_tokens)
        if total_chars >=# MAX_CHARS || total_tokens >=# MAX_TOKENS
            return Failure.new('Exceed Max Chars:' .. string(total_chars) .. "  Max Tokens: " .. string(total_tokens))
        endif
        const result_stack = ParseFirstLine(thisline_tokens, row)

        var result = result_stack[0]
        var stack = result_stack[1]
        var front_path = row
        var back_path  = row

        while (false ==# stack.front.Empty())
                && stack.front.Last().inner_value.is_first_line
                && (front_path <=# MAX_ROWS)
            front_path += 1
            thisline = getline(front_path)
            total_chars += len(thisline)

            thisline_tokens = Tokenize(thisline, front_path)
            total_tokens += len(thisline_tokens)
            if total_chars >=# MAX_CHARS || total_tokens >=# MAX_TOKENS
                return Failure.new('Exceed Max Chars:' .. string(total_chars) .. "  Max Tokens: " .. string(total_tokens))
            endif
            result += thisline_tokens
                ->map((_, ele) => {
                    return stack.PushFront(ele)
                })
                ->reduce((pre, curr) => pre + curr, [])
        endwhile

        while (false ==# stack.back.Empty())
                && stack.back.Last().inner_value.is_first_line
                && (back_path >=# 1)
            back_path -= 1
            thisline = getline(back_path)
            total_chars += len(thisline)

            thisline_tokens = Tokenize(thisline, back_path)
            total_tokens += len(thisline_tokens)
            if total_chars >=# MAX_CHARS || total_tokens >=# MAX_TOKENS
                return Failure.new('Exceed Max Chars:' .. string(total_chars) .. "  Max Tokens: " .. string(total_tokens))
            endif
            result += thisline_tokens->reverse()
                ->map((_, ele) => {
                    return stack.PushBack(ele)
                })
                ->reduce((pre, curr) => pre + curr, [])
        endwhile
        return Success.new([result, back_path, front_path])
    enddef

    def UpdateOnNeed(row: number, total: bool): Result
        const parse_result: Result = this.UpdateOnNeedHelper(row)
        if parse_result.IsFailure
            return parse_result
        endif
        const [match_lst, back_path, front_path] = parse_result.inner_value

        if total
            this.cache = {}
        endif

        for r in range(back_path, front_path)
            this.cache[r] = []
        endfor
        for match in match_lst
            this.cache[match.right.row]->insert(match, 0)
            this.cache[match.left.row]->insert(match,  0)
        endfor
        this.first_row = back_path
        this.second_row = front_path

        return Success.new('')
    enddef

    def UpdateOnCallback(match_lst: list<MatchPair>, start: number, end: number)
        for match in match_lst
            if this.cache->has_key(match.right.row)
                this.cache[match.right.row]->insert(match, 0)
            endif
            if this.cache->has_key(match.left.row)
                this.cache[match.left.row]->insert(match, 0)
            endif
        endfor
    enddef

    def ClearCache(clear_start: number, clear_end: number)
        for r in range(clear_start, clear_end)
            this.cache[r] = []
        endfor
    enddef

    def SearchMatchStack(cursor_pos: Position): Result
        if this.cache->has_key(string(cursor_pos.row)) ==# 0
            return Failure.new("Error! cache is Empty")
        endif

        if len(this.cache[cursor_pos.row]) ==# 0
            return Failure.new("Error! no MatchPair Found in this line")
        endif

        return Success.new(Max(this.cache[cursor_pos.row], cursor_pos))
    enddef
endclass

class PairManager
    static final id_cache:   dict<PairCache> = {}
    static var   last_match: Result = Failure.new("null match")

    static def HighLight(make_new_cache: bool = true)
        const [_, row, col, _]      = getpos('.')
        const bufid:      number    = bufnr()
        final cursor_pos: Position  = Position.new('', row, col)
        final cache:      PairCache = PairManager.Get(bufid)
        var   re_match:   Result    = cache.SearchMatchStack(cursor_pos)
        final winid:      number    = win_getid()

        if [re_match.IsFailure, last_match.IsFailure] ==# [true, true]
            OnlyBufType(true, false, true)
            re_match = cache.SearchMatchStack(cursor_pos)
            if false ==# re_match.IsFailure
                re_match.inner_value.HighLight()
            endif
        elseif [re_match.IsFailure, last_match.IsFailure] ==# [true, false]
            const l_match: MatchPair = PairManager.last_match.inner_value
            l_match.HighLightClear()
            OnlyBufType(true, false, true)
            re_match = cache.SearchMatchStack(cursor_pos)
            if false ==# re_match.IsFailure
                re_match.inner_value.HighLight()
            endif

        elseif [re_match.IsFailure, last_match.IsFailure] ==# [false, true]
            const r_match: MatchPair = re_match.inner_value
            r_match.HighLight()
        elseif [re_match.IsFailure, last_match.IsFailure] ==# [false, false]
            const r_match: MatchPair = re_match.inner_value
            const l_match: MatchPair = PairManager.last_match.inner_value

            l_match.HighLightClear()
            r_match.HighLight()
        endif
        PairManager.last_match = re_match
    enddef

    static def HighLightFlush(bufid: number)
        const start = reltimefloat(reltime())
        const [_, row, col, _]      = getpos('.')
        final cursor_pos: Position  = Position.new('', row, col)
        final cache:      PairCache = PairManager.Get(bufid)
        var   re_match:   Result    = cache.SearchMatchStack(cursor_pos)
        final winid:      number    = win_getid()

        if [re_match.IsFailure, last_match.IsFailure] ==# [true, true]
        elseif [re_match.IsFailure, last_match.IsFailure] ==# [true, false]
            const l_match: MatchPair = PairManager.last_match.inner_value
            l_match.HighLightClear()
        elseif [re_match.IsFailure, last_match.IsFailure] ==# [false, true]
            const r_match: MatchPair = re_match.inner_value
            r_match.HighLight()
        elseif [re_match.IsFailure, last_match.IsFailure] ==# [false, false]
            const r_match: MatchPair = re_match.inner_value
            const l_match: MatchPair = PairManager.last_match.inner_value

            if (winid !=# l_match.winid)
                || (true ==# r_match.hl_id.IsFailure)
                || (l_match.hl_id.inner_value !=# r_match.hl_id.inner_value)
                l_match.HighLightClear()
                r_match.HighLight()
            endif
        endif
        PairManager.last_match = re_match
    enddef

    static def UpdateOnNeed(bufid: number, row: number, total: bool): Result
        final cache: PairCache = PairManager.Get(bufid)
        const result = cache.UpdateOnNeed(row, total)
        return result
    enddef

    static def UpdateOnCallback(bufnr: number, matches: list<MatchPair>, start: number, end: number)
        final bufid: number    = bufnr
        final cache: PairCache = PairManager.Get(bufid)
        cache.UpdateOnCallback(matches, start, end)
    enddef

    static def ClearCache(bufid: number, clear_start: number, clear_end: number)
        final cache: PairCache = PairManager.Get(bufid)
        cache.ClearCache(clear_start, clear_end)
    enddef

    static def Get(bufid: number): PairCache
        if !PairManager.id_cache->has_key(string(bufid))
            PairManager.id_cache[bufid] = PairCache.new(bufid)
        endif
        return PairManager.id_cache[bufid]
    enddef

    static def IGmap()
        const l_match = PairManager.last_match
        if last_match.IsFailure
            return
        endif
        const match: MatchPair = last_match.inner_value

        if mode() ==# 'n'
            if match.left.row ==# match.right.row && match.left.bcol + match.left.len ==# match.right.bcol
                cursor(match.left.row, match.left.bcol)
                normal! a_
                cursor(match.left.row, match.left.bcol + match.left.len)
                normal! v
            else
                if match.right.bcol ==# 1
                    cursor(match.right.row - 1, len(getline(match.right.row - 1)))
                else
                    cursor(match.right.row, match.right.bcol - 1)
                endif
                normal! v
                cursor(match.left.row, match.left.bcol + 1)
            endif
        elseif mode() ==# 'v'
            normal! v
            if len(getline(match.left.row)) ==# match.left.bcol
                cursor(match.left.row + 1, 1)
            else
                cursor(match.left.row, match.left.bcol + match.left.len)
            endif
            normal! v
            if match.right.bcol ==# 1
                cursor(match.right.row - 1, len(getline(match.right.row - 1)))
            else
                cursor(match.right.row, match.right.bcol - 1)
            endif
        endif
        return
    enddef

    static def RemoveCache()
        const bufname = expand("<afile>")
        const bufid = bufnr(bufname)
        if PairManager.id_cache->keys()->index(string(bufid)) !=# -1
            PairManager.id_cache->remove(string(bufid))
        endif
    enddef

    static def AGmap()
        const l_match = PairManager.last_match
        if last_match.IsFailure
            return
        endif
        const match: MatchPair = last_match.inner_value
        if mode() ==# 'n'
            cursor(match.left.row, match.left.bcol)
            normal! v
            cursor(match.right.row, match.right.bcol)
        elseif mode() ==# 'v'
            normal! v
            cursor(match.left.row, match.left.bcol)
            normal! v
            cursor(match.right.row, match.right.bcol)
        endif
    enddef

    static def GHmap()
        const l_match = PairManager.last_match
        if last_match.IsFailure
            return
        endif
        const match: MatchPair = last_match.inner_value
        cursor(match.left.row, match.left.bcol)
    enddef
    static def GLmap()
        const l_match = PairManager.last_match
        if last_match.IsFailure
            return
        endif
        const match: MatchPair = last_match.inner_value
        cursor(match.right.row, match.right.bcol)
    enddef
    static def GRop()
        const l_match = PairManager.last_match
        if last_match.IsFailure
            return
        endif
        const match: MatchPair = last_match.inner_value
        cursor(match.left.row, match.left.bcol)
        const char  = getcharstr()
        MatchOper.Select(char, match)
    enddef
endclass

class MatchOper
    static def SetLines(match: MatchPair, lines: list<string>)
        if len(lines) ==# 1
            setline(match.left.row, lines[0])
        elseif len(lines) ==# 2
            setline(match.left.row, lines[0])
            setline(match.right.row, lines[1])
        else
            throw "MatchOper.SetLines: lines has more than two lines!"
        endif
    enddef

    static def DealBasicCase(match: MatchPair, ProcessLeft: func(string): string, ProcessRight: func(string): string): list<string>
        if match.left.row ==# match.right.row
            return [ProcessLeft(ProcessRight(getline(match.left.row)))]
        else
            const first_line  = getline(match.left.row)
            const second_line = getline(match.right.row)
            return [ProcessLeft(first_line), ProcessRight(second_line)]
        endif
    enddef

    static def DeleteMatchProcess(match: MatchPair): list<func(string): string>
        const ProcessRight = (line: string): string => {
            var splitted = line->split('\zs')
            const index: number = charidx(line, match.right.bcol - 1)
            splitted->remove(index, index + strcharlen(match.right.content) - 1)

            return splitted->join('')
        }

        const ProcessLeft = (line: string): string => {
            var splitted = line->split('\zs')
            const index: number = charidx(line, match.left.bcol - 1)
            splitted->remove(index, index + strcharlen(match.left.content) - 1)

            return splitted->join('')
        }
        return [ProcessLeft, ProcessRight]
    enddef

    static def ChangePairProcess(match: MatchPair, new_left: string, new_right: string): list<func(string): string>
        const [DeleteLeft, DeleteRight] = DeleteMatchProcess(match)
        const ChangeLeft = (line: string): string => {
            const index: number = charidx(line, match.left.bcol - 1)
            return DeleteLeft(line)->split('\zs')->insert(new_left, index)->join('')
        }
        const ChangeRight = (line: string): string => {
            const index: number = charidx(line, match.right.bcol - 1)
            return DeleteRight(line)->split('\zs')->insert(new_right, index)->join('')
        }
        return [ChangeLeft, ChangeRight]
    enddef


    static def DeletePair(match: MatchPair)
        const [ProcessLeft, ProcessRight] = MatchOper.DeleteMatchProcess(match)
        const lines: list<string> = MatchOper.DealBasicCase(match, ProcessLeft, ProcessRight)
        MatchOper.SetLines(match, lines)
    enddef

    static def ChangePair(match: MatchPair, new_left: string, new_right: string)
        const [ProcessLeft, ProcessRight] = MatchOper.ChangePairProcess(match, new_left, new_right)
        const lines = MatchOper.DealBasicCase(match, ProcessLeft, ProcessRight)
        MatchOper.SetLines(match, lines)
    enddef
    static def Select(char: string, match: MatchPair)
        if char ==# 'd'
            MatchOper.DeletePair(match)
            popup_notification(['delete' .. match.left.content .. match.right.content], {'time': 700})
        elseif char ==# 'c'
            const new_char = input('please enter')
            MatchOper.ChangePair(match, new_char, new_char)
            popup_notification(['replaced by' .. [new_char, new_char]->join(' ')], {'time': 700})
        elseif InChar(char)
            const [left, right] = g:gmotion_pair->copy()->filter((idx: number, p: list<string>): bool => p->index(char) !=# -1)[0]
            MatchOper.ChangePair(match, left, right)
            popup_notification(['replaced by' .. [left, right]->join(' ')], {'time': 700})
        else
            popup_notification(['undefined motion'], {'time': 700})
        endif
    enddef
endclass

def OnlyBufType(insert_leave: bool = true, total: bool = false, do_nothing: bool = false)
    const bufid = bufnr()
    const [_, row1, _, _] = getpos("'[")
    const [_, row2, _, _] = getpos("']")
    var [start,       end]       = [row1, row2]
    var [clear_start, clear_end] = [row1, row2]
    var direct_call_job = false

    if total
        [start, clear_start] = [1, 1]
        end = line('$')
        clear_end = end
    else
        const [_, row, col, _] = getpos('.')
        const ab_result = ParseLineRange(row)
        if ab_result.IsFailure
            direct_call_job = true
            clear_start = 1
            clear_end = line('$')
            start = 1
            end = clear_end
        else
            const [a, b] = ab_result.inner_value
            [start, end] = [a, b]
            if a ==# -1 || b ==# -1
                clear_start = 0
                clear_end   = 0

                return
            elseif insert_leave
                clear_start = a
                clear_end = b
            elseif row1 !=# row2 || (len(getreg('"')) > 1)
                clear_start = row1
                clear_end   = line('$')
            endif
        endif
    endif
    PairManager.ClearCache(bufid, clear_start, clear_end)
    if direct_call_job
        CallOnJob(bufid, start, end, do_nothing)
    else
        const result = PairManager.UpdateOnNeed(bufid, line('.'), !insert_leave)
        if result.IsFailure
            CallOnJob(bufid, start, end, do_nothing)
        else
        endif
    endif
enddef

aug Gmotion
autocmd!
au User Init InitBuffer()
au VimEnter    * ++once InitBuffer()
au BufDelete   * PairManager.RemoveCache()
aug END



ono ig <ScriptCmd> PairManager.IGmap()<CR>
ono ag <ScriptCmd> PairManager.AGmap()<CR>
vno ig <ScriptCmd> PairManager.IGmap()<CR>
vno ag <ScriptCmd> PairManager.AGmap()<CR>
ono gh <ScriptCmd> PairManager.GHmap()<CR>
ono gl <ScriptCmd> PairManager.GLmap()<CR>
nno gh <ScriptCmd> PairManager.GHmap()<CR>
nno gl <ScriptCmd> PairManager.GLmap()<CR>
vno gh <ScriptCmd> PairManager.GHmap()<CR>
vno gl <ScriptCmd> PairManager.GLmap()<CR>
nno gr <ScriptCmd> PairManager.GRop()<CR>

def CreateParseJob(bufid: number, start: number, end: number): job
    const base = start

    const job = job_start('/home/rongzi/.config/scripts/pairparse', {
        "noblock": 0,
        "in_mode": "json",
        "out_mode": "raw",
        "timeout": 2000,
        "stoponexit": "kill",
        "out_cb": (ch: channel, msg: string) => {
            const matches = From_tree_sitter(msg, base)
            PairManager.UpdateOnCallback(bufid, matches, start, end)
            PairManager.HighLightFlush(bufid)
        }
    })
    const channel = job_getchannel(job)
    ch_sendexpr(channel, getbufline(bufid, start, end))
    ch_close_in(channel)
    return job
enddef

def InitAutoCmd(bufid: number, start: number, end: number): job
    const base = start
    const job = job_start('/home/rongzi/.config/scripts/pairparse', {
        "noblock":  0,
        "in_mode":  "json",
        "out_mode": "raw",
        "timeout": 2000,
        "stoponexit": "kill",
        "out_cb": (ch: channel, msg: string) => {
            const matches = From_tree_sitter(msg, base)
            PairManager.UpdateOnCallback(bufid, matches, start, end)
            PairManager.HighLightFlush(bufid)
            aug GmotionUpdate
            autocmd!
            au BufReadPost * InitBuffer()
            au TextChanged,InsertLeave * OnlyBufType(false)
            au TextChanged,CursorMoved,InsertLeave * PairManager.HighLight()
            aug END
        }
    })
    const channel = job_getchannel(job)
    ch_sendexpr(channel, getbufline(bufid, start, end))
    ch_close_in(channel)
    return job
enddef


var current_job: Result = Failure.new("null job")

def CallOnJob(bufid: number, start: number, end: number, do_nothing: bool = true)
    if !current_job.IsFailure
        if  do_nothing
            return
        endif
        if job_status(current_job.inner_value) !=# 'dead'
            job_stop(current_job.inner_value, 'kill')
        endif
    endif
    current_job = Call_test(bufid, start, end)
enddef

def Call_test(bufid: number, start: number, end: number): Result
    if [-1, -1] ==# [start, end]
        PairManager.HighLightFlush(bufid)
        return Failure.new("null job")
    endif
    return Success.new(CreateParseJob(bufid, start, end))
enddef

def InitBuffer()
    const bufid = bufnr()
    const [start, end] = [1, line('$')]
    PairManager.ClearCache(bufid, start, end)
    const job = InitAutoCmd(bufid, start, end)
    current_job = Success.new(job)
enddef

command -nargs=0 GmotionTest doautocmd User Init
