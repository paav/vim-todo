" Vim global plugin for handling tasks
" Last Change:	2015 May 02
" Maintainer:	Alexey Panteleiev <paav at inbox dot ru>

if exists('g:loaded_todo')
    " finish
endif

let g:loaded_todo = 1

let s:old_cpo = &cpo
set cpo&vim

let s:BUFNAME_MAIN = 'TodoMain'
let s:BUFNAME_EDIT = 'TodoEdit'
let s:MAINWIN_W = 65
let s:DIR_BASE = escape(expand('<sfile>:p:h:h'), '\')
let s:DIR_LIB = s:DIR_BASE . '/lib'
let s:FILE_DB = s:DIR_BASE . '/data/todo.db'
let s:TAG_MARK = '#'

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

function! s:WinIsVisible(bufname) abort
    if s:GetWinNum(a:bufname) != -1
        return 1
    endif
    return 0
endfunction


" Class HelpWidget
" ============================================================ 

let s:HelpWidget = {
    \'_TEXT_INFO': ['Press ? for help'],
    \'_TEXT_HELP': [
            \'"j": move cursor down',
            \'"k": move cursor up',
            \'"n": new task',
            \'"e": edit task'
        \]
\}

function! s:HelpWidget.create() abort
    let self._isvisible = 0
    let self._curtext = self._TEXT_INFO
    let self._prevtext = []
    return copy(self)
endfunction

function! s:HelpWidget.render() abort
    let l:save_opt = &l:modifiable
    let &l:modifiable = 1

    if !empty(self._prevtext) 
        let prev_text_len = len(self._prevtext)
        exe '1,' . prev_text_len . '$delete'
    endif

    call append(0, self._curtext)
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


" Class TasksTableWidget
" ============================================================ 

let s:TasksTableWidget = {}

function! s:TasksTableWidget.create() abort
    let self._isvisible = 0
    let self._tasks = pyeval('tasklist.gettasks()')
    return copy(self)
endfunction

function! s:TasksTableWidget.update() abort
    let l:lasttask = self._tasks[self._curidx]
    let self._tasks = pyeval('tasklist.gettasks()')

    " TODO: move to separate function
    let l:lastlnum = self._baselnum + len(self._tasks) - 1
    " TODO: repeated code
    let l:save_opt = &l:modifiable
    let &l:modifiable = 1
    exe self._baselnum . ',' . l:lastlnum . 'delete'
    call self._renderBody()
    let &l:modifiable = l:save_opt

    call cursor(self._gettasklnum(l:lasttask), 0)
endfunction

function! s:TasksTableWidget.render() abort
    let l:save_opt = &l:modifiable
    let &l:modifiable = 1
    " exe a:lnum . ',$delete'

    call self._renderHead()
    call self._renderBody()

    let self._isvisible = 1
    let &l:modifiable = l:save_opt
endfunction

function! s:TasksTableWidget._renderHead() abort
    let @o = printf('%-10s%-32s%-10s%-10s', 'Created', 'Title', 'Tag', 'Pri') 
    let @o .= "\n" . repeat('-', 60)
    put o
    let self._baselnum = line('.') + 1
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

    return printf('%-13s%-32s%-10s%-5s',
        \self._tstotimeformat(a:task.create_date, '%-d %b'),
        \a:task.title, tagname, a:task.priority) 
endfunction

function! s:TasksTableWidget._tstotimeformat(ts, format)
    return pyeval(
        \'datetime.fromtimestamp(' . string(a:ts) . ').strftime("'
            \ . a:format . '")')
endfunction

function! s:TasksTableWidget.getcurtask() abort
    let l:baselnum = self._baselnum
    let l:curlnum = line('.')

    if l:curlnum < l:baselnum
        return
    endif

    let self._curidx = l:curlnum - l:baselnum

    return self._tasks[self._curidx]
endfunction

function! s:TasksTableWidget.getcuridx() abort
    return self._curidx
endfunction

function! s:TasksTableWidget._gettasklnum(task) abort
    let l:i = 0

    for l:t in self._tasks 
        if l:t.id == a:task.id
            return self._idxtolnum(l:i)
        endif

        let l:i += 1
    endfor

    return -1
endfunction

function! s:TasksTableWidget.update_task(idx, newtask) abort
    let self._tasks[a:idx] = a:newtask
    let l:lnum = self._idxtolnum(a:idx)
    let l:newrow = self._tasktorow(a:newtask)

    " TODO: same as in self.render()
    let l:save_opt = &l:modifiable
    let &l:modifiable = 1
    call setline(l:lnum, l:newrow)
    let &l:modifiable = l:save_opt
endfunction

function! s:TasksTableWidget._idxtolnum(idx) abort
    let l:maxidx = len(self._tasks) - 1

    if a:idx < -l:maxidx - 1 || a:idx > l:maxidx
        throw 'TasksTableWidget:wrongindex'
    endif

    return self._baselnum + (a:idx < 0 ? l:maxidx + 1 + a:idx : a:idx)
endfunction

function! s:TasksTableWidget.add_task(task) abort
    call add(self._tasks, a:task)
    let l:newlnum = self._idxtolnum(-1)
    let l:save_opt = &l:modifiable
    let &l:modifiable = 1
    call setline(l:newlnum, self._tasktorow(a:task))
    let &l:modifiable = l:save_opt
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

function! s:Open() abort
        python reload(todo)
    " if !exists('g:todo_py_loaded')
        python import sys
        python import vim
        exe 'python sys.path.append("' . s:DIR_LIB . '")'
        python import todo 
        python from todo import tasklist
        python from todo import Task
        python from datetime import datetime
        exe 'python todo.setdb("' . s:FILE_DB . '")'
        let g:todo_py_loaded = 1
    " endif

    if s:WinIsVisible(s:BUFNAME_MAIN)
        return
    endif

    call s:OpenMainWin()
    setlocal modifiable
    1,$delete
    setlocal nomodifiable
    
    " if !exists('b:help_widget')
        let b:help_widget = s:HelpWidget.create()
    " endif

    " if !b:help_widget.isVisible()
        call b:help_widget.render()
    " endif

    let b:tasks_table = s:TasksTableWidget.create()
    call b:tasks_table.render()
endfunction

function! s:Close() abort
    call s:GotoWin(s:BUFNAME_MAIN)
    close
endfunction

function! s:GotoWin(bufname) abort
    exe s:GetWinNum(a:bufname) . 'wincmd w' 
endfunction

function! s:GetWinNum(bufname) abort
    return bufwinnr(bufnr(a:bufname))
endfunction

function! s:Toggle()
    if s:WinIsVisible(s:BUFNAME_MAIN)
        call s:Close()
    else
        call s:Open()
    endif
endfunction

function! s:OpenMainWin() abort
    exe 'topleft ' . s:MAINWIN_W . 'vnew ' . s:BUFNAME_MAIN
endfunction

function! s:TodoClose()
    exe bufwinnr(bufnr('Todo')) . "wincmd w"
    quit
endfunction

" TODO: problem with write to curret dir access
function! s:OpenEditWin() abort
    silent exe 'new ' . s:BUFNAME_EDIT
endfunction

function! s:EditTask(task) abort
    call s:OpenEditWin()
    let old_undolevels = &l:undolevels
    let &l:undolevels = -1

    if !a:task.isnew
        let @o = a:task.title

        if a:task.body != ''
            let @o .= "\n" . a:task.body
        endif

        if !empty(a:task.tags)
            let l:tagnames = []
            for l:tag in a:task.tags
                let l:tagnames = add(l:tagnames, l:tag.name)
            endfor
            let @o .= "\n" . s:TAG_MARK . join(l:tagnames, ' ') 
        endif

        put o | 1delete | write

        let &l:undolevels = old_undolevels
    endif

    let b:task = a:task
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

    python newtask = todo.Task(vim.eval('l:task'), vim.eval('l:task.isnew'),
                              \vim.eval('l:task.tags'))
    python newtask.save()

    let l:tasks_table =  getbufvar(s:BUFNAME_MAIN, 'tasks_table')
    call s:GotoWin(s:BUFNAME_MAIN)

    if l:task.isnew
        python from pprint import pprint
        python pprint(newtask.__dict__)
        python pprint(newtask.todict())
        call l:tasks_table.add_task(pyeval('newtask.todict()'))
    else
        call l:tasks_table.update_task(l:tasks_table.getcuridx(), l:task)
    endif
endfunction

function! s:UpdateTask(task)
    silent 1,$g/^\s*$/d

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

function! s:DeleteTask(task) abort
    let l:YES = 'yes'
    let l:PROMPT = "Type '" . l:YES . "' to delete task at cursor: "
    let l:answer = input(l:PROMPT, '')
    redraw | echo ''

    if l:answer !=# l:YES
        return
    endif

    exe 'python Task().delbyid(' . a:task.id . ')'
    call b:tasks_table.deltask() 
endfunction

function! s:_ChangePriorityBy(value) abort
    let l:task = b:tasks_table.getcurtask() 

    " TODO: repeated code
    python newtask = todo.Task(vim.eval('l:task'), vim.eval('l:task.isnew'),
                              \vim.eval('l:task.tags'))
    python newtask.changepri(vim.eval('a:value'))
    python newtask.save()

    call b:tasks_table.update()
endfunction

function! s:RaisePriority() abort
    call s:_ChangePriorityBy(1)
endfunction

function! s:DropPriority() abort
    call s:_ChangePriorityBy(-1)
endfunction

function! s:TodoRefresh()
    python refresh()
endfunction

function! s:TodoApplyTagFilter()
    python apply_tag_filter()
endfunction

function! s:ApplyMainBufMaps()
    nnoremap <silent> <buffer> n :call <SID>EditTask({'isnew': 1})<CR>
    nnoremap <silent> <buffer> <nowait> gd :call <SID>DeleteTask(b:tasks_table.getcurtask())<CR>
    nnoremap <buffer> e :call <SID>EditTask(b:tasks_table.getcurtask())<CR>
    nnoremap <silent> <buffer> <nowait> = :call <SID>RaisePriority()<CR>
    nnoremap <silent> <buffer> - :call <SID>DropPriority()<CR>
    nnoremap <silent> <buffer> x :call <SID>TodoFinish()<CR>
    nnoremap <silent> <buffer> f :call <SID>TodoApplyTagFilter()<CR>
    nnoremap <silent> <buffer> ? :call b:help_widget.toggle()<CR>
endfunction

function! s:ApplyMainBufSettings()
    setlocal buftype=nofile
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
endfunction

let &cpo = s:old_cpo
unlet s:old_cpo
