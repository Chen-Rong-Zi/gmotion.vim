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
g:loaded_gmotion = 1
const g:pair = [
    ['(', ')'],
    ['[', ']'],
    ['{', '}'],
    ['<', '>'],
    ['"', '"'],
    ["'", "'"],
]
const g:special_pair = [
    ['"', '"'],
    ["'", "'"],
]

const lpart = g:pair->copy()->map((i, v) => v[0])
const rpart = g:pair->copy()->map((i, v) => v[1])
const chars = lpart + rpart
const schar = g:special_pair->copy()->map((i, v) => v[0])

def InPair(p: list<string>): bool
    return g:pair->index(p) !=# -1
enddef

def InX(X: list<string>): func(string): bool
    return (char: string): bool => X->index(char) !=# -1
enddef

const InChar  = InX(chars)
const InRpart = InX(rpart)
const InLpart = InX(lpart)
const InSchar = InX(schar)

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
    def new(content: string, row: number, col: number)
        this.content = content
        this.row = row
        this.bcol = col
    enddef
    def EqualMe(other: Position): bool
        return this.row ==# other.row && this.bcol ==# other.bcol
    enddef
    def BeforeMe(other: Position): bool
        if this.EqualMe(other)
            return false
        else
            return !this.AfterMe(other)
        endif
    enddef
    def AfterMe(other: Position): bool
        if other.row ># this.row
            return true
        elseif other.row ==# this.row && other.bcol > this.bcol
            return true
        else
            return false
        endif
    enddef
    def Distance(anchor: Position): number
        const big_bit   = abs(anchor.row - this.row)
        const small_bit = abs(anchor.bcol - this.bcol)
        return big_bit * 10 + small_bit
    enddef
endclass

class MatchPair
    public var left:  Position
    public var right: Position
    public var highlight_id: list<number> = []
    def new(left: Position, right: Position)
        this.left  = left
        this.right = right
    enddef
    def InMe(pos: Position): bool
        if pos.BeforeMe(this.right) || pos.AfterMe(this.left)
            return false
        else
            return true
        endif
    enddef
    def Distance(anchor: Position): number
        return min([anchor.Distance(this.left), anchor.Distance(this.right)])
    enddef
    def HighLight()
        this.highlight_id->insert(matchaddpos('MatchParen', [[this.left.row,  this.left.bcol,  len(this.left.content)]]),  0)
        this.highlight_id->insert(matchaddpos('MatchParen', [[this.right.row, this.right.bcol, len(this.right.content)]]), 0)
    enddef
    def HighLightClear()
        for id in this.highlight_id
            matchdelete(id)
        endfor
        this.highlight_id = []
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

class PairCache
    public var winid: number
    public var cache: dict<list<MatchPair>> = {}
    public var last_match: Result
    public var stamp: float
    public var first_row:  number = 1
    public var second_row: number = 1

    def new(winid: number)
        this.winid = winid
        this.stamp = reltimefloat(reltime())
        this.last_match = Failure.new("init value")
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
        const passby: float    = timestamp - this.stamp
        this.stamp = timestamp
        var linecnt: number
        if count !=# 0
            linecnt = count
        elseif passby <# 0.5
            linecnt = 2
        elseif passby <# 1.0
            linecnt = 5
        elseif passby <# 5
            linecnt = 10
        elseif passby <# 10
            linecnt = &lines / 2
        elseif passby <# 20
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

        final result: list<MatchPair> = this.cache[cursor_pos.row]
        ->copy()
        ->sort((match0: MatchPair, match1: MatchPair) => {
            const d0: number = match0.Distance(cursor_pos)
            const d1: number = match1.Distance(cursor_pos)
            if d0 ==# 0
                return -1
            elseif d1 ==# 0
                return 1
            else
                return d0 - d1
            endif
        })
        if len(result) ==# 0
            return Failure.new("Error! result is Empty")
        else
            return Success.new(result[0])
        endif
    enddef
endclass

class PairManager
    static final id_cache: dict<PairCache> = {}

    static def HighLightClear(winid: number)
        if PairManager.highlighted_pair->keys()->index(string(winid)) ==# -1
            PairManager.highlighted_pair[winid] = []
        endif
        for match in PairManager.highlighted_pair[winid]
            match.HighLightClear()
        endfor
    enddef

    static def HighLight()
        const [_, row, col, _] = getpos('.')
        const cursor_pos = Position.new('', row, col)
        const winid: number    = win_getid()
        const cache: PairCache = PairManager.Get(winid)
        if !cache.last_match.IsFailure
            const last_match: MatchPair = cache.last_match.inner_value
            last_match.HighLightClear()
        endif
        cache.last_match = Failure.new("Erorr! Does not have a g:pair that matches " .. string(row) .. " line")

        if row <# cache.first_row || row ># cache.second_row
            cache.UpdateOnCondition((cache.second_row - cache.first_row) * 2)
        endif

        const re_match: Result = cache.SearchMatchStack(cursor_pos)
        if !re_match.IsFailure
            const match: MatchPair = re_match.inner_value
            match.HighLight()
            cache.last_match = Success.new(match)
        endif
    enddef

    static def UpdateOnCondition(count: number = 0)
        const winid: number    = win_getid()
        const cache: PairCache = PairManager.Get(winid)
        cache.UpdateOnCondition(count)
    enddef

    static def Get(winid: number): PairCache
        if PairManager.id_cache->keys()->index(string(winid)) ==# -1
            PairManager.id_cache[winid] = PairCache.new(winid)
        endif
        return PairManager.id_cache[winid]
    enddef

    static def IGmap()
        const winid: number    = win_getid()
        const cache: PairCache = PairManager.Get(winid)
        if cache.last_match.IsFailure
            return
        endif
        const match: MatchPair = cache.last_match.inner_value

        if mode() ==# 'n'
            if match.left.row ==# match.right.row && match.left.bcol + len(match.left.content) ==# match.right.bcol
                # case0: left and right are too close () {} []
                cursor(match.left.row, match.left.bcol)
                # add _
                normal! a_
                cursor(match.left.row, match.left.bcol + len(match.left.content))
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
                cursor(match.left.row, match.left.bcol + len(match.left.content))
            endif
            normal! v
            cursor(match.right.row, match.right.bcol - 1)
        endif
        return
    enddef

    static def AGmap()
        const winid: number    = win_getid()
        const cache: PairCache = PairManager.Get(winid)
        if cache.last_match.IsFailure
            return
        endif
        const match: MatchPair = cache.last_match.inner_value
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
        const winid: number    = win_getid()
        const cache: PairCache = PairManager.Get(winid)
        if cache.last_match.IsFailure
            return
        endif
        const match: MatchPair = cache.last_match.inner_value
        cursor(match.left.row, match.left.bcol)
    enddef
    static def GLmap()
        const winid: number    = win_getid()
        const cache: PairCache = PairManager.Get(winid)
        if cache.last_match.IsFailure
            return
        endif
        const match: MatchPair = cache.last_match.inner_value
        cursor(match.right.row, match.right.bcol)
    enddef
    static def GRop()
        const winid: number    = win_getid()
        const cache: PairCache = PairManager.Get(winid)
        if cache.last_match.IsFailure
            return
        endif
        const match: MatchPair = cache.last_match.inner_value
        cursor(match.left.row, match.left.bcol)
        match.HighLight()
        const char  = getcharstr()
        MatchOper.Select(char, match)
        match.HighLightClear()
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
            const lines = getline(match.left.row, match.right.row)
            return [ProcessLeft(lines[0]), ProcessRight(lines[1])]
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
            echom 'delete ' .. match.left.content .. match.right.content
            # popup_notification(['delete' .. match.left.content .. match.right.content], {'time': 1000})
        elseif char ==# 'c'
            const new_char = input('please enter')
            MatchOper.ChangePair(match, new_char, new_char)
            # popup_notification(['replaced by' .. [new_char, new_char]->join(' ')], {})
            echom 'replaced by ' .. [new_char, new_char]->join(' ')
        elseif InChar(char)
            const [left, right] = g:pair->copy()->filter((idx: number, p: list<string>): bool => p->index(char) !=# -1)[0]
            MatchOper.ChangePair(match, left, right)
            # popup_notification(['replaced by' .. [left, right]->join(' ')], {})
            echom 'replaced by ' .. [left, right]->join(' ')
        else
            # popup_notification(['未表示的motion'], {})
            echom 'undefined motion!'
        endif
    enddef
endclass

aug Gmotion
au User      Init PairManager.UpdateOnCondition(line('$'))
au TextChanged  * PairManager.UpdateOnCondition()
au InsertLeave  * PairManager.UpdateOnCondition()
au CursorMoved  * PairManager.HighLight()
au TextChanged  * PairManager.HighLight()
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
