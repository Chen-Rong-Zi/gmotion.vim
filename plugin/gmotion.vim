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
        ['<', '>'],
        ['"', '"'],
        ["'", "'"],
        ['`', '`'],
    ]
endif

g:loaded_gmotion = 1
const special_pair = g:gmotion_pair->copy()->filter((idx: number, match: list<string>) => match[0] ==# match[1])
const lpart = g:gmotion_pair->copy()->map((i: number, v: list<string>) => v[0])
const rpart = g:gmotion_pair->copy()->map((i: number, v: list<string>) => v[1])
const chars = lpart + rpart
const schar = special_pair->copy()->map((i: number, v: list<string>) => v[0])

const InPair  = (lst:  list<string>): bool => g:gmotion_pair->index(lst) !=# -1
const InChar  = (char: string):       bool => chars->index(char)  !=# -1
const InRpart = (char: string):       bool => rpart->index(char)  !=# -1
const InLpart = (char: string):       bool => lpart->index(char)  !=# -1
const InSchar = (char: string):       bool => schar->index(char)  !=# -1

abstract class Result
    var inner_value: any
    var IsFailure: bool
endclass

class Success extends Result
    # unit :: a -> Success a
    def new(value: any)
        this.inner_value = value
        this.IsFailure = false
    enddef
endclass

class Failure extends Result
    # unit :: a -> Failure a
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
    def new(content: string, row: number, col: number)
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
    return big_bit * 10 + small_bit
enddef

class MatchPair
    static var match_count = 0
    public var left:  Position
    public var right: Position
    public var hl_id: Result
    public final match_id: number

    def new(left: Position, right: Position)
        this.left  = left
        this.right = right
        this.hl_id = Failure.new("null hl_id")
        MatchPair.match_count += 1
        this.match_id = MatchPair.match_count
    enddef
    def InMe(pos: Position): bool
        if BeforeMe(pos, this.right) || AfterMe(pos, this.left)
            return false
        else
            return true
        endif
    enddef
    def Distance(anchor: Position): number
        return min([Distance(anchor, this.left), Distance(anchor, this.right)])
    enddef
    def HighLight()
        this.hl_id = Success.new(matchaddpos(g:gmotion_highligh_group, [[this.left.row,  this.left.bcol,  this.left.len], [this.right.row, this.right.bcol, this.right.len]]))
    enddef
    def HighLightClear(winid: number)
        if win_id2tabwin(winid) ==# [0, 0]
            return
        endif
        matchdelete(this.hl_id.inner_value, winid)
        this.hl_id = Failure.new("hl_id is Null")
    enddef
endclass

class Stack
    public var content: list<Position>
    def new()
        this.content = []
    enddef
    def Top(): Result
        if len(this.content) !=# 0
            return Success.new(this.content[0])
        else
            return Failure.new("长度为0，不能切片")
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

class MatchParseStack
    public final part_stack: Stack

    def new()
        this.part_stack = Stack.new()
    enddef

    def PushLeft(pos: Position)
        this.part_stack.Push(pos)
    enddef

    def PushRight(r_pos: Position): list<MatchPair>
        const top: Result = this.part_stack.Top()
        if top.IsFailure ==# true
            return []
        endif

        const l_pos: Position = top.inner_value
        if InPair([l_pos.content, r_pos.content])
            this.part_stack.Pop()
            return [MatchPair.new(l_pos, r_pos)]
        else
            return []
        endif
    enddef

    def PushSpecial(r_pos: Position): list<MatchPair>
        const top: Result = this.part_stack.Top()
        if top.IsFailure ==# true
            this.PushLeft(r_pos)
            return []
        endif

        const l_pos: Position = top.inner_value
        if InPair([l_pos.content, r_pos.content])
            this.part_stack.Pop()
            return [MatchPair.new(l_pos, r_pos)]
        else
            this.PushLeft(r_pos)
            return []
        endif
    enddef
endclass

def Enumerate(lst: list<any>): list<any>
    return lst->copy()->map((idx, c) => [c, idx])
enddef

def ParseLine(line: string, row: number, stack: MatchParseStack): list<any>
    var result: list<any>  = []
    const characters = line->split('\zs')
    const char_idx = Enumerate(characters)
    var bcol: number = 0
    for [char, idx] in char_idx
        if ! InChar(char)
            # do nothing
        elseif InSchar(char)
            const pos: Position = Position.new(char, row, bcol + 1)
            result += stack.PushSpecial(pos)
        elseif InLpart(char)
            const pos: Position = Position.new(char, row, bcol + 1)
            stack.PushLeft(pos)
        else
            const pos: Position = Position.new(char, row, bcol + 1)
            result += stack.PushRight(pos)
        endif
        bcol += len(char)
    endfor
    return [result, stack]
enddef

def ParseLines(first_row: number, second_row: number): list<MatchPair>
    final matches: list<MatchPair> = []
    var stack: MatchParseStack = MatchParseStack.new()
    for [line, idx] in Enumerate(getline(first_row, second_row))
        const parse_result = ParseLine(line, first_row + idx, stack)
        matches->extend(parse_result[0])
        stack = parse_result[1]
    endfor
    return matches
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
    public final cache: dict<list<MatchPair>>
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

        for row in range(row0, row1)
            this.cache[row] = []
        endfor
        for match in match_lst
            this.cache[match.right.row]->insert(match, 0)
            this.cache[match.left.row]->insert(match,  0)
        endfor
    enddef

    def UpdateOnCondition(count: number = 0)
        const timestamp: float = reltimefloat(reltime())
        const passby:    float = timestamp - this.stamp
        this.stamp = timestamp
        var linecnt: number
        if count !=# 0
            linecnt = count
        elseif passby <# 0.5
            linecnt = 5
        elseif passby <# 1.0
            linecnt = 10
        elseif passby <# 5
            linecnt = 20
        elseif passby <# 10
            linecnt = &lines
        else
            linecnt = line('$')
        endif
        const [_, row, _, _] = getpos('.')
        this.first_row  = max([1,         row - linecnt])
        this.second_row = min([line('$'), row + linecnt])
        this.Update(this.first_row, this.second_row)
    enddef

    def SearchMatchStack(cursor_pos: Position): Result
        if this.cache->keys()->index(string(cursor_pos.row)) ==# -1
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
    static var   winid:      number = win_getid()

    static def HighLight()
        const [_, row, col, _]      = getpos('.')
        const bufid:      number    = bufnr()
        const win_id:     number    = win_getid()
        final cursor_pos: Position  = Position.new('', row, col)
        final cache:      PairCache = PairManager.Get(bufid)
        final re_match:   Result    = cache.SearchMatchStack(cursor_pos)

        if re_match.IsFailure
            # case0: re_match: Failure, last_match: Failure
            if (row <# cache.first_row || row ># cache.second_row)
                cache.UpdateOnCondition(&lines)
            endif
            if !PairManager.last_match.IsFailure
                # case1: re_match: Failure, last_match: Success
                const l_match: MatchPair = PairManager.last_match.inner_value
                l_match.HighLightClear(PairManager.winid)
            endif
        elseif !re_match.IsFailure && PairManager.last_match.IsFailure
            # case2: re_match: Success, last_match: Failure
            const r_match: MatchPair = re_match.inner_value
            r_match.HighLight()
            PairManager.winid = win_id
        elseif !re_match.IsFailure && !PairManager.last_match.IsFailure
            # case3: re_match: Success, last_match: Failure
            const r_match: MatchPair = re_match.inner_value
            const l_match: MatchPair = PairManager.last_match.inner_value
            if r_match.match_id != l_match.match_id
                l_match.HighLightClear(PairManager.winid)
                r_match.HighLight()
            endif
            PairManager.winid = win_id
        endif
        PairManager.last_match = re_match

    enddef

    static def UpdateOnCondition(count: number = 0)
        final bufid: number    = bufnr()
        final cache: PairCache = PairManager.Get(bufid)
        cache.UpdateOnCondition(count)
    enddef

    static def Get(bufid: number): PairCache
        if PairManager.id_cache->keys()->index(string(bufid)) ==# -1
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
                # case0: left and right are too close () {} []
                cursor(match.left.row, match.left.bcol)
                # add _
                normal! a_
                cursor(match.left.row, match.left.bcol + match.left.len)
                normal! v
            else
                # case1: left and right are in diffent lines
                if match.right.bcol ==# 1
                    # case2: right is the first character
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
                # case0: left is the last character, move to the first character in the next line
                cursor(match.left.row + 1, 1)
            else
                # case1: left is not the last character, move to the next character
                cursor(match.left.row, match.left.bcol + match.left.len)
            endif
            normal! v
            cursor(match.right.row, match.right.bcol - 1)
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
            # echom 'delete ' .. match.left.content .. match.right.content
            popup_notification(['delete' .. match.left.content .. match.right.content], {'time': 700})
        elseif char ==# 'c'
            const new_char = input('please enter')
            MatchOper.ChangePair(match, new_char, new_char)
            popup_notification(['replaced by' .. [new_char, new_char]->join(' ')], {'time': 700})
            # echom 'replaced by ' .. [new_char, new_char]->join(' ')
        elseif InChar(char)
            const [left, right] = g:gmotion_pair->copy()->filter((idx: number, p: list<string>): bool => p->index(char) !=# -1)[0]
            MatchOper.ChangePair(match, left, right)
            popup_notification(['replaced by' .. [left, right]->join(' ')], {'time': 700})
            # echom 'replaced by ' .. [left, right]->join(' ')
        else
            popup_notification(['undefined motion'], {'time': 700})
            # echom 'undefined operator!'
        endif
    enddef
endclass

aug Gmotion
au User      Init PairManager.UpdateOnCondition(&lines)
au TextChanged  * PairManager.UpdateOnCondition()
au InsertLeave  * PairManager.UpdateOnCondition()
au CursorMoved  * PairManager.HighLight()
au TextChanged  * PairManager.HighLight()
au BufDelete    * PairManager.RemoveCache()
aug END
doautocmd User Init
# au User Init PairManager.UpdateSyntaxTree(line('$'))


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

command -nargs=?  -count=100 GmotionUpdate PairManager.UpdateOnCondition(<count>)
