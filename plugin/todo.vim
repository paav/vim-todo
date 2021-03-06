" Vim global plugin for handling tasks
" Last Change:	2015 May 25
" Maintainer:	Alexey Panteleiev <paav at inbox dot ru>

if exists('g:loaded_todo')
    finish
endif

let g:loaded_todo = 1

let s:old_cpo = &cpo
set cpo&vim

let s:BUFNAME_MAIN = 'TodoMain'
let s:BUFNAME_EDIT = 'TodoEdit'
let s:VERSION      = '0.1.0'
let s:MAINWIN_W    = 65
let s:DIR_BASE     = escape(expand('<sfile>:p:h:h'), '\')
let s:DIR_LIB      = s:DIR_BASE . '/lib'
let s:DBFILE_DEF   = s:DIR_BASE . '/data/todo.db'
let s:DBFILE       = s:DBFILE_DEF
let s:TAG_MARK     = '#'
let s:MSG_NOTASKS  = 'There are no tasks under the cursor.'

command! Todo call s:Open()
command! TodoToggle call s:Toggle()
command! TodoClose call s:Close()

augroup todo
    autocmd!
    exe 'autocmd BufNewFile ' . s:BUFNAME_MAIN . ' call s:ApplyMainBufSettings()'
    exe 'autocmd BufNewFile ' . s:BUFNAME_MAIN . ' call s:ApplyMainBufMaps()'
    exe 'autocmd BufNewFile ' . s:BUFNAME_EDIT . ' call s:ApplyEditBufSettings()'
    exe 'autocmd BufWinLeave ' . s:BUFNAME_EDIT . ' call s:OnEditBufExit()'
augroup END

function! s:ApplyMainBufMaps()
    nnoremap <silent> <buffer>          gn :call <SID>NewTask()<CR>
    nnoremap <silent> <buffer> <nowait> gd :call <SID>DeleteTask()<CR>
    nnoremap <silent> <buffer>          ge :call <SID>EditTask()<CR>
    nnoremap <silent> <buffer> <nowait> =  :call <SID>ChangePriority('+1')<CR>
    nnoremap <silent> <buffer>          -  :call <SID>ChangePriority(-1)<CR>
    nnoremap <silent> <buffer>          gp :call <SID>SetPriority()<CR>
    nnoremap <silent> <buffer>          ga :call <SID>FinishTask()<CR>
    nnoremap <silent> <buffer>          gf :call <SID>ApplyTagFilter()<CR>
    nnoremap <silent> <buffer>          gh :call <SID>ToggleHelp()<CR>
endfunction

function! s:ApplyMainBufSettings()
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal nobuflisted
    setlocal nomodifiable
    setlocal nonumber
    setlocal cursorline
    setlocal filetype=newtodo
    setlocal conceallevel=3
    setlocal concealcursor=nc
endfunction

function! s:ApplyEditBufSettings()
    setlocal noswapfile
    setlocal nonumber
    setlocal nobuflisted
    setlocal bufhidden=wipe
    setlocal textwidth=0
endfunction

" Class HelpWidget {{{
" ============================================================ 

let s:HelpWidget = {
    \'_TEXT_INFO': ['Press gh for help'],
    \'_TEXT_HELP': [
            \'"Vim-todo plugin v' . s:VERSION,
            \'"gn: new task      = : raise pri   ga: finish task',
            \'"ge: edit task     - : drop pri    gf: filter by tags',
            \'"gd: delete task   gp: set pri     gh: toggle help',
        \]
\}

function! s:HelpWidget.create() abort
    let self._isvisible = 0
    let self._curtext = self._TEXT_INFO
    let self._prevtext = []
    let self._firstlnum = 1
    return copy(self)
endfunction

function! s:HelpWidget.render() abort
    let l:save_opt = &l:modifiable
    let &l:modifiable = 1

    if !empty(self._prevtext) 
        let l:oldpos = getcurpos()

        let prev_text_len = len(self._prevtext)
        exe 'silent 1,' . prev_text_len . '$delete'

        " Correct lnum after deletion
        let l:oldpos[1] -= prev_text_len
        call setpos('.', l:oldpos)
    endif

    call append(self._firstlnum - 1, self._curtext)

    let self._isvisible = 1
    let &l:modifiable = l:save_opt
endfunction

function! s:HelpWidget.isVisible() abort
    return self._isvisible
endfunction

function! s:HelpWidget.toggle() abort
    if empty(self._prevtext)
        let self._prevtext = self._curtext
        let self._curtext = self._TEXT_HELP
    else
        let l:curtext_save = self._curtext
        let self._curtext = self._prevtext
        let self._prevtext = l:curtext_save
    endif
    
    call self.render()
endfunction

function! s:HelpWidget.getlastlnum() abort
    return len(self._curtext) + 1
endfunction
"}}}

" Class TasksTableWidget {{{
" ============================================================ 

let s:TasksTableWidget = {}

function! s:TasksTableWidget.create() abort
    let self._isvisible = 0
    python tasklist.load()
    let self._tasks = pyeval('tasklist.tovimlist()')
    let self._curidx = 0
    let self._MSG_NOTASKS = '<there are no such tasks>'
    let self._CLASSNAME = 'TasksTableWidget'
    return copy(self)
endfunction

function! s:TasksTableWidget.update(...) abort
    let l:ishard = !exists('a:1') ? 0 : a:1

    try
        let l:lasttask = self.getcurtask() 
        let l:lastlnum = line('.')
    catch /TasksTableWidget:CursorPosError/ 
        let l:lasttask = {}
    endtry

    if l:ishard
        python tasklist.load()
    endif

    let self._tasks = pyeval('tasklist.tovimlist()')

    " TODO: repeated code
    let l:saved_opt = &l:modifiable
    let &l:modifiable = 1
    exe 'silent ' . self._baselnum . ',' . '$' . 'delete'

    if !empty(self._tasks)
        call self._renderBody()
    else
        call setline(line('.') + 1, self._MSG_NOTASKS)
    endif

    let &l:modifiable = l:saved_opt
    
    let l:curlnum = empty(l:lasttask) ? 0 : self._gettasklnum(l:lasttask)
    call cursor(l:curlnum == -1 ? l:lastlnum : l:curlnum, 0)
endfunction

function! s:TasksTableWidget.filterbytags(tagnames) abort
    python tasklist.filter = { 'tagnames': vim.eval('a:tagnames') }
    call self.update()
endfunction

function! s:TasksTableWidget.setfirstlnum(lnum) abort
    let self._firstlnum = a:lnum
    let self._baselnum = a:lnum + self._headlen
endfunction

function! s:TasksTableWidget.render() abort
    let self._firstlnum = line('.') + 1

    let l:save_opt = &l:modifiable
    let &l:modifiable = 1
    " exe a:lnum . ',$delete'

    call self._renderHead()
    call self._renderBody()

    let self._baselnum = self._firstlnum + self._headlen
    let self._isvisible = 1
    let &l:modifiable = l:save_opt
endfunction

function! s:TasksTableWidget._renderHead() abort
    let self._headlen = 2
    let @o = printf('%-9s%-38s%-13s%-3s', 'Created', 'Title', 'Tag', 'Pri') 
    let @o .= "\n" . repeat('─', 64)
    put o
endfunction

function! s:TasksTableWidget._renderBody() abort
    for task in self._tasks
        call setline(line('.') + 1, self._tasktorow(task))
        call cursor(line('.') + 1, col('.'))
    endfor
endfunction

function! s:TasksTableWidget._tasktorow(task) abort
    " Pick only first tag
    let tag = get(a:task.tags, 0, {})
    let tagname = !empty(tag) ? tag.name : '' 

    " Marks for syntax highlighting
    let l:hl = ''

    if a:task.priority > 5
        let l:hl = '!'
    elseif a:task.priority > 3
        let l:hl = '?'
    endif

    return printf(l:hl . '%-12s%-38s%-13s%2s',
        \self._tstotimeformat(a:task.create_date, '%d %b'),
        \self._cut(a:task.title, 34), self._cut(tagname, 10), a:task.priority)
endfunction

function! s:TasksTableWidget._cut(str, len)
    let l:TAIL = '...'
    let l:taillen = len(l:TAIL)

    return len(a:str) <= a:len ? a:str : a:str[:a:len - l:taillen] . l:TAIL
endfunction

function! s:TasksTableWidget._tstotimeformat(ts, format)
    return pyeval(
        \'datetime.fromtimestamp(' . string(a:ts) . ').strftime("'
            \ . a:format . '")')
endfunction

function! s:TasksTableWidget.getcurtask() abort
    try
        let l:idx = self.getcuridx2()
    catch /TasksTableWidget:CursorPosError/ 
        throw v:exception
    endtry

    if getline(self._idxtolnum(l:idx)) ==# self._MSG_NOTASKS
        throw self._CLASSNAME
            \. ':CursorPosError: there is no task under the cursor.'
    endif

    return self._tasks[l:idx]
endfunction

function! s:TasksTableWidget.getcuridx() abort
    return self._curidx
endfunction

function! s:TasksTableWidget.getcuridx2() abort
    let l:idx = line('.') - self._baselnum 

    if l:idx < 0
        throw self._CLASSNAME . ":CursorPosError: cursor isn't in table body."
    endif

    return l:idx
endfunction

function! s:TasksTableWidget._gettasklnum(task) abort
    if !has_key(a:task, 'id')
        throw "TasksTableWidget:_gettasklnum: there is no 'id' key in the dict"
    endif

    let l:i = 0

    for l:t in self._tasks 
        if l:t.id == a:task.id
            return self._idxtolnum(l:i)
        endif

        let l:i += 1
    endfor

    return -1
endfunction

function! s:TasksTableWidget._idxtolnum(idx) abort
    let l:len = len(self._tasks)
    let l:maxidx = l:len != 0 ? l:len - 1 : 0

    if a:idx < -l:maxidx - 1 || a:idx > l:maxidx
        throw 'TasksTableWidget:wrongindex'
    endif

    return self._baselnum + (a:idx < 0 ? l:maxidx + 1 + a:idx : a:idx)
endfunction

function! s:TasksTableWidget.deltask(...) abort
    if a:0 > 1
        throw 'TasksTableWidget:toomanyargs'
    endif

    let l:idx = exists('a:1') ? a:1 : self._curidx
    let l:lnum = self._idxtolnum(l:idx)

    unlet self._tasks[l:idx]

    " TODO: repeated code
    let l:save_opt = &l:modifiable
    let &l:modifiable = 1
    exe l:lnum . 'delete'
    let &l:modifiable = l:save_opt
endfunction
" }}}

function! s:Open() abort
    if !exists('g:todo_py_loaded')
        python import sys
        exe 'python sys.path.append("' . s:DIR_LIB . '")'
        python import vim
        python import todo
        python from todo import tasklist
        python from todo import Task
        python from todo import Tag
        python from datetime import datetime
        python from time import time
        let g:todo_py_loaded = 1
    endif

    if !exists('g:todo_dbfile')
        let g:todo_dbfile = s:DBFILE_DEF
    endif

    if s:DBFILE !=# g:todo_dbfile
        let s:DBFILE = g:todo_dbfile
        python import todo
        python from todo import tasklist
        python from todo import Task
        python from todo import Tag
        exe 'silent! bwipeout ' . s:BUFNAME_MAIN
    endif

    exe 'python todo.setdb("' . s:DBFILE . '")'

    if s:BufIsvisible(s:BUFNAME_MAIN)
        return
    endif

    if s:BufExists(s:BUFNAME_MAIN)
        call s:OpenMainBuf()
        call b:tasks_table.update()
    else
        call s:CreateMainBuf()

        let b:help_widget = s:HelpWidget.create()
        call b:help_widget.render()

        let b:tasks_table = s:TasksTableWidget.create()
        call b:tasks_table.render()
    endif
endfunction

function! s:Close() abort
    call s:GotoWin(s:BUFNAME_MAIN)
    close
endfunction

function! s:Toggle()
    if s:BufIsvisible(s:BUFNAME_MAIN)
        call s:Close()
    else
        call s:Open()
    endif
endfunction

function! s:ToggleHelp() abort
    call b:help_widget.toggle()
    let l:lnum = b:help_widget.getlastlnum()
    call b:tasks_table.setfirstlnum(l:lnum + 1)
endfunction

function! s:OpenMainBuf() abort
    exe 'topleft ' . s:MAINWIN_W . 'vs +buffer' . bufnr(s:BUFNAME_MAIN)
endfunction

function! s:CreateMainBuf() abort
    exe 'topleft ' . s:MAINWIN_W . 'vnew ' . s:BUFNAME_MAIN
endfunction

function! s:GotoWin(bufname) abort
    exe s:GetWinNum(a:bufname) . 'wincmd w' 
endfunction

" TODO: problem with write to curret dir access
function! s:OpenEditWin() abort
    silent exe 'new ' . s:BUFNAME_EDIT
endfunction

function! s:GetWinNum(bufname) abort
    return bufwinnr(bufnr(a:bufname))
endfunction

function! s:BufIsvisible(bufname) abort
    if s:GetWinNum(a:bufname) != -1
        return 1
    endif

    return 0
endfunction

function! s:BufExists(bufname) abort
    return bufnr(a:bufname) != -1 ? 1 : 0
endfunction

function! s:Echo(msg) abort
    let l:ECHO_PFX = 'Todo: '
    echo l:ECHO_PFX . a:msg 
endfunction

function! s:EditTask(...) abort
    try
        let l:task = exists('a:1') ? a:1 : b:tasks_table.getcurtask()
    catch /TasksTableWidget:CursorPosError/
        call s:Echo(s:MSG_NOTASKS)
        return
    endtry

    call s:OpenEditWin()
    let old_undolevels = &l:undolevels
    let &l:undolevels = -1

    if !l:task.isnew
        let @o = l:task.title

        if l:task.body != ''
            let @o .= "\n" . l:task.body
        endif

        if !empty(l:task.tags)
            let l:tagnames = []
            for l:tag in l:task.tags
                let l:tagnames = add(l:tagnames, l:tag.name)
            endfor
            let @o .= "\n" . s:TAG_MARK . join(l:tagnames, ' ') 
        endif

        put o | 1delete | write

        let &l:undolevels = old_undolevels
    endif

    let b:task = l:task
endfunction

function! s:NewTask() abort
    call s:EditTask({'isnew': 1})
endfunction

function! s:OnEditBufExit()
    if &modified
        edit! %
    endif

    let l:task = s:UpdateTask(copy(b:task))

    " Delete buf file
    call delete(s:BUFNAME_EDIT)

    if empty(l:task) || l:task == b:task
        return
    endif

    let l:tasks_table =  getbufvar(s:BUFNAME_MAIN, 'tasks_table')
    let l:attrs = {'title': l:task.title, 'body': l:task.body}
    python attrslist = vim.eval('l:task.tags')
    python tags = Tag().createmany(attrslist) if attrslist else []

    if l:task.isnew
        python task = Task(vim.eval('l:task'))
        python tasklist.add(task)
    else
        python task = tasklist.findbyid(int(vim.eval('l:task.id')))
        " Link to task in tasklist
        python task.attrs = vim.eval('l:attrs')
    endif

    python task.tags = tags
    python task.save()

    call s:GotoWin(s:BUFNAME_MAIN)

    call b:tasks_table.update()
endfunction

function! s:UpdateTask(task) abort
    " Remove empty lines at the top/end
    silent! %s#\v%^($\n\s*)+## 
    silent! %s#\v($\n\s*)+%$##

    let l:firstline = getline(1)
    let l:lastlnum = line('$')

    if l:lastlnum == 1 && l:firstline == ''
        return {}
    endif

    let a:task.title = getline(1)

    let l:tags = []
    let l:body = ''

    if l:lastlnum > 1
        let l:taglinepat = '\v^' . s:TAG_MARK . '(\w+\s*)+'
        let l:lastline = getline(l:lastlnum)

        if l:lastline =~ l:taglinepat
            " Delete tag line
            $d
            let l:lastlnum -= 1
            let l:tags = s:CreateTags(l:lastline[1:])
        endif
    endif

    if l:lastlnum > 1
        let l:bodylines = getline(2, l:lastlnum)
        let l:body = join(l:bodylines, "\n") 
    endif

    let a:task.body = l:body
    let a:task.tags = l:tags

    return a:task
endfunction

function! s:CreateTags(line)
    let l:tags = []
    let l:taskid = b:task.isnew ? '' : b:task.id
    
    for l:name in split(a:line)
        let l:tags = add(l:tags, {'task_id': l:taskid, 'name': l:name})
    endfor

    return l:tags
endfunction

function! s:DeleteTask() abort
    " TODO: repeated code
    try
        let l:id = b:tasks_table.getcurtask().id
    catch /TasksTableWidget:CursorPosError/
        call s:Echo(s:MSG_NOTASKS)
        return
    endtry

    let l:YES = 'yes'
    let l:PROMPT = "Type '" . l:YES . "' to delete task at cursor: "
    let l:answer = input(l:PROMPT, '')
    redraw | echo ''

    if l:answer !=# l:YES
        return
    endif

    python << py
Task().delbyid(int(vim.eval('l:id')))
tasklist.delbyid(int(vim.eval('l:id')))
py
    call b:tasks_table.update()
endfunction

function! s:ChangePriority(value) abort
    " TODO: repeated code
    try
        let l:id = b:tasks_table.getcurtask().id
    catch /TasksTableWidget:CursorPosError/
        call s:Echo(s:MSG_NOTASKS)
        return
    endtry

    python << py
id = int(vim.eval('l:id'))
task = tasklist.findbyid(id)
task.priority = vim.eval('a:value')
task.save()
py
    call b:tasks_table.update(1)
endfunction

function! s:SetPriority() abort
    let l:pri = input('Set priority to: ')
    call s:ChangePriority(l:pri)
endfunction

function! s:ApplyTagFilter()
    let l:tagnames = split(input('Filter by tags: '))
    call b:tasks_table.filterbytags(l:tagnames)
endfunction

function! s:FinishTask()
    " TODO: repeated code
    try
        let l:id = b:tasks_table.getcurtask().id
    catch /TasksTableWidget:CursorPosError/
        call s:Echo(s:MSG_NOTASKS)
        return
    endtry

    python << py
id = int(vim.eval('l:id'))
task = tasklist.findbyid(id)
task.done_date = time()
task.save()
tasklist.delbyid(int(vim.eval('l:id')))
py
    call b:tasks_table.update()
endfunction

let &cpo = s:old_cpo
unlet s:old_cpo

" vim:fdm=marker
