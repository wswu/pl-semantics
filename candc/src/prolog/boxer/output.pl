
:- module(output,[printHeader/4,
                  printFooter/1,
                  printSem/4,
		  printDerList/2,
                  printBox/2]).

:- use_module(boxer(xdrs2xml),[xdrs2xml/2,der2xml/3]).
:- use_module(boxer(drs2fdrs),[instDrs/1]).
:- use_module(boxer(printDrs),[printDrs/3]).
:- use_module(boxer(betaConversionDRT),[betaConvert/2]).
:- use_module(boxer(tuples),[write_tuples/2]).

:- use_module(semlib(drs2tex),[drs2tex/2]).
:- use_module(semlib(drs2tacitus),[printTAC/2]).
:- use_module(semlib(options),[option/2]).
:- use_module(semlib(errors),[warning/2]).

:- use_module(library(lists),[member/2,append/3]).

/* ------------------------------------------------------------------------
   Options
------------------------------------------------------------------------ */

printOptions([],Stream):- !, 
   nl(Stream).

printOptions([X|L],Stream):- 
   write(Stream,X), tab(Stream,1),
   printOptions(L,Stream).

 
/* ------------------------------------------------------------------------
   Print header: --format no
------------------------------------------------------------------------ */

printHeader(_,_,_,_):-
   option('--format',no), !.

/* ------------------------------------------------------------------------
   Print header: --format prolog
------------------------------------------------------------------------ */

printHeader(Stream,_,Command,Options):-
   option('--format',prolog), !,
   format(Stream,'%%% This output was generated by the following command:~n',[]),
   format(Stream,'%%% ~p ',[Command]),
   printOptions(Options,Stream),
   ( option('--semantics',drs), !,
     format(Stream,'~n:- multifile     sem/3, id/2.',[]),
     format(Stream,'~n:- discontiguous sem/3, id/2.',[]),
     format(Stream,'~n:- dynamic       sem/3, id/2.~n',[])
   ; true ).

/* ------------------------------------------------------------------------
   Print header: --format latex
------------------------------------------------------------------------ */

printHeader(Stream,_,_,_):-
   option('--format',latex), !,
   write(Stream,'\\documentclass[10pt]{article}'), nl(Stream),
   nl(Stream),
   write(Stream,'\\usepackage{a4wide}'),           nl(Stream),
   nl(Stream),
   write(Stream,'\\newcommand{\\drs}[2]'),         nl(Stream),
   write(Stream,'{'),                              nl(Stream),
   write(Stream,'   \\begin{tabular}{|l|}'),       nl(Stream),
   write(Stream,'   \\hline'),                     nl(Stream),
   write(Stream,'   #1'),                          nl(Stream),
   write(Stream,'   \\\\'),                        nl(Stream),
   write(Stream,'   ~ \\vspace{-2ex} \\\\'),       nl(Stream),
   write(Stream,'   \\hline'),                     nl(Stream),
   write(Stream,'   ~ \\vspace{-2ex} \\\\'),       nl(Stream),
   write(Stream,'   #2'),                          nl(Stream),
   write(Stream,'   \\\\'),                        nl(Stream),
   write(Stream,'   \\hline'),                     nl(Stream),
   write(Stream,'   \\end{tabular}'),              nl(Stream),
   write(Stream,'}'),                              nl(Stream),
   nl(Stream),
   write(Stream,'\\parindent 0pt'),                nl(Stream),
   write(Stream,'\\parskip 10pt'),                  nl(Stream),
   nl(Stream),
   write(Stream,'\\begin{document}'),              nl(Stream),
   write(Stream,'\\sf \\tiny'),                    nl(Stream),
   nl(Stream).

/* ------------------------------------------------------------------------
   Print header: --format dot
------------------------------------------------------------------------ */

printHeader(_,_,_,_):-
   option('--format',dot), !.

/* ------------------------------------------------------------------------
   Print header: --format xml
------------------------------------------------------------------------ */

printHeader(Stream,Version,_,_):-
   option('--format',xml), !,
   format(Stream,'<?xml version="1.0" encoding="UTF-8"?>~n',[]),
   format(Stream,'<!DOCTYPE xdrs-output SYSTEM "src/data/boxer/xdrs.dtd">~n',[]),
   format(Stream,'<xdrs-output version="~p">~n',[Version]).


/* ------------------------------------------------------------------------
   Print header: failed, generate warning
------------------------------------------------------------------------ */

printHeader(_,_,_,_):-
   option('--format',Format), 
   option('--semantics',Semantics), 
   warning('unable to output header for --semantics ~p --format ~p',[Semantics,Format]).


/* ------------------------------------------------------------------------
   Print footer
------------------------------------------------------------------------ */

printFooter(Stream):-
   option('--format',xml), 
   format(Stream,'</xdrs-output>~n',[]).

printFooter(Stream):-
   option('--format',latex), !,
   format(Stream,'\\end{document}~n',[]).

printFooter(_).


/* ========================================================================
   Print Utterance +  Semantic Representation
======================================================================== */

printSem(Stream,_Id,_Index,Ders):-
   option('--semantics',der), !,             %%% derivation
   printDerList(Stream,Ders).

printSem(Stream,Id,Index,XDRS):-
   XDRS = xdrs(Tags,_),
   printUtterance(Stream,Tags),
   printXDRS(Stream,Id,Index,XDRS).


/* =======================================================================
   Print Derivations
========================================================================*/

printDerList(_,[]):- !.

printDerList(Stream,[der(I,Der)|L]):- 
   option('--format',xml), !,
   der2xml(Der,I,Stream),
   printDerList(Stream,L). 

printDerList(Stream,[der(I,Der)|L]):- 
   write(Stream,'der( '), write(Stream,I), write(Stream,', '),
   printDer(Der,Stream),
   write(Stream,' ).'), nl(Stream), !,
   printDerList(Stream,L). 

printDerList(Stream,[der(I,_)|L]):- 
   warning('cannot print derivation ~p',[I]),
   printDerList(Stream,L). 


/*========================================================================
   Print Derivation (bit of a hack right now!)
========================================================================*/

printDer(Comb,Stream):-
   Comb = t(Cat,Tok,Sem,Att,_), !,
   betaConvert(Sem,Red),
   \+ \+ ( instDrs(Red), 
           write_term(Stream,t(Red,Cat,Tok,Att),[numbervars(true),quoted(true)]) ).

printDer(Comb,Stream):- 
   Comb =.. [Rule,Cat,_,Sem,_,_,T],
   member(Rule,[ftr,btr,tc]), !, 
   write(Stream,Rule), 
   write(Stream,'('),
   write(Stream,Cat),
   write(Stream,','),
   betaConvert(Sem,Red),
   \+ \+ ( instDrs(Red), 
           write_term(Stream,Red,[numbervars(true),quoted(true)]) ),
   write(Stream,','),
   printDer(T,Stream),
   write(Stream,')').

printDer(Comb,Stream):- 
   Comb =.. [Rule,Cat,Sem,_,_,L,R], !,
   write(Stream,Rule), 
   write(Stream,'('),
   write(Stream,Cat),
   write(Stream,','),
   betaConvert(Sem,Red),
   \+ \+ ( instDrs(Red), 
           write_term(Stream,Red,[numbervars(true),quoted(true)]) ),
   write(Stream,','),
   printDer(L,Stream),
   write(Stream,','),
   printDer(R,Stream), 
   write(Stream,')').

printDer(Comb,Stream):- 
   Comb =.. [Rule,Cat,_,Sem,_,_,L,R], !,
   write(Stream,Rule), 
   write(Stream,'('),
   write(Stream,Cat),
   write(Stream,','),
   betaConvert(Sem,Red),
   \+ \+ ( instDrs(Red), 
           write_term(Stream,Red,[numbervars(true),quoted(true)]) ),
   write(Stream,','),
   printDer(L,Stream),
   write(Stream,','),
   printDer(R,Stream), 
   write(Stream,')').

printDer(Comb,_):- 
   warning('cannot print the derivation ~p',[Comb]).


/* ========================================================================
   Print DRS
======================================================================== */

printXDRS(Stream,_,_,XDRS):-
   option('--semantics',drs),
   option('--format',no), !,
   printBox(Stream,XDRS).

printXDRS(Stream,Id,_Index,XDRS):-
   option('--semantics',drs),
   option('--format',xml), !,
   format(Stream,'<xdrs xml:id="~p">~n',[Id]),
   xdrs2xml(XDRS,Stream),
   format(Stream,'</xdrs>~n',[]).

printXDRS(Stream,_Id,_Index,XDRS):-
   option('--semantics',drs), 
   option('--format',latex), !,  
   XDRS = xdrs(_Tags,DRS),
   drs2tex(DRS,Stream),
   nl(Stream), nl(Stream).

printXDRS(Stream,Id,Index,XDRS):-
   option('--semantics',drs), !,
   XDRS = xdrs(Tags,DRS),
   format(Stream,'id(~q,~p).~n',[Id,Index]),
   format(Stream,'sem(~p,',[Index]),
   printStuff(Tags,Stream,','),
   nl(Stream),
   printStuff(DRS,Stream,').'),
   printBox(Stream,DRS),
   nl(Stream).


/* ========================================================================
   Print PDRS
======================================================================== */

printXDRS(Stream,_,_,XDRS):-
   option('--semantics',pdrs),
   option('--format',no), !,
   printBox(Stream,XDRS).

printXDRS(Stream,Id,_Index,XDRS):-
   option('--semantics',pdrs),
   option('--format',xml), !,
   format(Stream,'<xdrs xml:id="~p">~n',[Id]),
   xdrs2xml(XDRS,Stream), 
   printBox(Stream,XDRS),
   format(Stream,'</xdrs>~n',[]).

printXDRS(Stream,Id,Index,XDRS):-
   option('--semantics',pdrs),
   XDRS = xdrs(Tags,DRS),
   format(Stream,'id(~q,~p).~n',[Id,Index]),
   format(Stream,'sem(~p,',[Index]),
   printStuff(Tags,Stream,','),
   nl(Stream),
   printStuff(DRS,Stream,').'),
   printBox(Stream,XDRS),
   nl(Stream).


/* ========================================================================
   Print DRG
======================================================================== */

printXDRS(Stream,_Id,_Index,XDRS):-
   option('--semantics',drg), !,   
   XDRS = xdrs(_,Tuples),
   write_tuples(Tuples,Stream),
   nl(Stream).


/* ========================================================================
   Print FOL
======================================================================== */

printXDRS(Stream,Id,Index,XDRS):-
   option('--semantics',fol), !,
   format(Stream,'id(~q,~p).~n',[Id,Index]),
   XDRS = xdrs(_Tags,FOL),
   numbervars(FOL,0,_),
   format(Stream,'fol(~p,',[Index]), 
   write_term(Stream,FOL,[numbervars(true),quoted(true)]),
   write(Stream,').'), nl(Stream).


/* ========================================================================
   Print TACITUS
======================================================================== */

printXDRS(Stream,Id,Index,XDRS):-
   option('--semantics',tacitus), !,
   format(Stream,'id(~q,~p).~n',[Id,Index]),
   XDRS = xdrs(Tags,TAC),
   printTags(Tags,Stream,''),
   printTAC(TAC,Stream).


/*========================================================================
   Print Box
========================================================================*/

printBox(Stream,XDRS):-
   option('--box',true), 
   option('--format',xml), !,
   format(Stream,'~n<!-- ~n',[]),
   leftMargin(Margin),
   printDrs(Stream,XDRS,Margin),
   format(Stream,'--> ~n~n',[]).

printBox(Stream,XDRS):-
   option('--box',true), !,
   nl(Stream),
   leftMargin(Margin), 
   printDrs(Stream,XDRS,Margin).

printBox(_,_).


/* ========================================================================
   Left Margin (for DRS printing)
======================================================================== */

leftMargin(Margin):- option('--format',prolog), !, Margin = '%%% '.
leftMargin(Margin):- option('--format',latex),  !, Margin = '%%% '.
leftMargin(Margin):- option('--format',dot),    !, Margin = '# '.
leftMargin(Margin):- Margin = ''.


/*========================================================================
   Print Utterance
========================================================================*/

printUtterance(Stream,Words):-
   option('--format',prolog), !,
   format(Stream,'%%% ',[]),
   printWords(Words,Stream),
   nl(Stream).

printUtterance(Stream,Words):-
   option('--format',latex), !,
   write(Stream,'\\section*{'),
   printWords(Words,Stream),
   write(Stream,'}'), nl(Stream).

printUtterance(Stream,Words):-
   option('--format',dot), !,
   format(Stream,'# ',[]),
   printWords(Words,Stream),
   nl(Stream).

printUtterance(Stream,Words):-
   option('--format',xml), !,
   format(Stream,'<!-- ',[]),
   printWords(Words,Stream),
   format(Stream,'--> ~n~n',[]).

printUtterance(Stream,Words):-
   option('--format',no), !,
   printWords(Words,Stream),
   nl(Stream).


/*========================================================================
   Print Words
========================================================================*/

printWords([],_):- !.

printWords([ID:[tok:Tok|R]|L],Stream):- 
   option('--format',xml),
   atom_concat('--',Rest,Tok), !,
   atom_concat('-',Rest,New),
   printWords([ID:[tok:New|R]|L],Stream).

printWords([_ID:[tok:Tok|_]|L],Stream):- !,
   format(Stream,'~w ',[Tok]),
   printWords(L,Stream).

printWords([_Unknown|L],Stream):- !,
   printWords(L,Stream).


/*========================================================================
   Print Stuff
========================================================================*/

printStuff(Stuff,Stream,Closing):-
   numbervars(Stuff,1,_),
   write_term(Stream,Stuff,[numbervars(true),quoted(true)]),
   format(Stream,'~p',[Closing]).


/*========================================================================
   Print Tags
========================================================================*/

printTags([],Stream,Ending):- 
   write(Stream,Ending). 

printTags([ID:[T|Ags]|L],Stream,_):- !,
   write(Stream,ID), write(Stream,' '), 
   printTags([T|Ags],Stream,'\n'),
   printTags(L,Stream,'').

printTags([_:V|L],Stream,Ending):- !,
   write(Stream,V), write(Stream,' '), 
   printTags(L,Stream,Ending).

