
% boxer.pl, by Johan Bos

/*========================================================================
   File Search Paths
========================================================================*/

file_search_path(semlib,     'src/prolog/lib').
file_search_path(boxer,      'src/prolog/boxer').
file_search_path(knowledge,  'src/prolog/boxer/knowledge').
file_search_path(lex,        'src/prolog/boxer/lex').


/*========================================================================
   Load other libraries
========================================================================*/

:- use_module(library(lists),[member/2,select/3]).

:- use_module(boxer(ccg2drs),[ccg2drs/3,udrs2drs/2]).
:- use_module(boxer(input),[openInput/0,identifyIDs/1,preferred/2]).
:- use_module(boxer(output),[printHeader/4,printFooter/1,printSem/4,printBox/2]).
:- use_module(boxer(evaluation),[initEval/0,reportEval/0]).
:- use_module(boxer(version),[version/1]).
:- use_module(boxer(printCCG),[printCCG/2]).
:- use_module(boxer(transform),[preprocess/8]).
:- use_module(boxer(drs2fdrs),[eqDrs/2,instDrs/1]).
:- use_module(xdrs2xml,[der2xml/2]).
:- use_module(boxer(betaConversionDRT),[betaConvert/2]).

:- use_module(semlib(errors),[error/2,warning/2]).
:- use_module(semlib(options),[option/2,parseOptions/2,setOption/3,
                               showOptions/1,setDefaultOptions/1]).


/*========================================================================
   Main
========================================================================*/

box(_,_):-
   option(Option,do), 
   member(Option,['--version','--help']), !, 
   version,
   help.

box(Command,Options):-
   openInput,
   openOutput(Stream),
   version(Version),
   printHeader(Stream,Version,Command,Options),
   initEval,
   box(Stream), !,
   printFooter(Stream),
   close(Stream), !,
   reportEval.
   
box(_,_):-
   setOption(boxer,'--help',do), !,
   help.


/*------------------------------------------------------------------------
   Perform depending on input type
------------------------------------------------------------------------*/

box(Stream):-
   input:inputtype(drs), !,
   findall(I,input:sem(I,_,_,_,_),List),
   resolveList(List,1,Stream).

box(Stream):-
   input:inputtype(ccg), !,
   identifyIDs(List),
   buildList(List,1,Stream).


/*------------------------------------------------------------------------
   Open Output File
------------------------------------------------------------------------*/

openOutput(Stream):-
   option('--output',Output),
   atomic(Output), 
   \+ Output=user_output, 
   ( access_file(Output,write), !,
     open(Output,write,Stream,[encoding(utf8)])
   ; error('cannot write to specified file ~p',[Output]),
     Stream=user_output ), !.

openOutput(user_output).


/*------------------------------------------------------------------------
   Context Parameters
------------------------------------------------------------------------*/

contextParameters([],_,[]):- !.

contextParameters(L1,Old,L3):- 
   select(poss(Pos),L1,L2), !,
   contextParameters(L2,[poss(Pos)|Old],L3).

contextParameters(['DOCID':DOCID|L1],Pos,[year:Year,month:Month,day:Day|L2]):- 
   atom_chars(DOCID,Chars),
   ( Chars = [_,_,_,'_','E','N','G','_',Y1,Y2,Y3,Y4,M1,M2,D1,D2,'.'|_]
   ; Chars = ['d','i','r','_',Y1,Y2,Y3,Y4,M1,M2,D1,D2|_]
   ; Chars = ['A','P','W',Y1,Y2,Y3,Y4,M1,M2,D1,D2|_]
   ; Chars = ['N','Y','T',Y1,Y2,Y3,Y4,M1,M2,D1,D2|_]
   ; Chars = ['X','I','E',Y1,Y2,Y3,Y4,M1,M2,D1,D2|_] ), !,
   atom_chars(Year,[Y1,Y2,Y3,Y4]), 
   atom_chars(Month,[M1,M2]), 
   atom_chars(Day,[D1,D2]), !,
   contextParameters(L1,Pos,L2).

contextParameters([role(A,B1,C1)|L1],Pos,[role(A,B2,C2)|L2]):- !,
   correct(Pos,B1,B2),
   correct(Pos,C1,C2),
   contextParameters(L1,Pos,L2).

contextParameters([target(A,B1,C1)|L1],Pos,[target(A,B2,C2)|L2]):- !,
   correct(Pos,B1,B2),
   correct(Pos,C1,C2),
   contextParameters(L1,Pos,L2).

contextParameters([_|L1],Pos,L2):- !,
   contextParameters(L1,Pos,L2).

contextParameters(_,_,[]).


correct([],N,N).

correct([poss(X)|L],N1,N3):-
   (X < N1, !, N2 is N1 + 1; N2 = N1),
   correct(L,N2,N3).



/*------------------------------------------------------------------------
   Print CCG derivations
------------------------------------------------------------------------*/

printCCGs([],_).

printCCGs([N|L],Stream):-  
   preferred(N,CCG0),
   preprocess(N,CCG0,CCG1,_,_,_,1,_), !,
   printCCG(CCG1,Stream), 
   printCCGs(L,Stream).

printCCGs([N|L],Stream):-  
   preferred(N,_), !,
   warning('cannot produce derivation for ~p',[N]),
   printCCGs(L,Stream).

printCCGs([N|L],Stream):-  
   warning('no syntactic analysis for ~p',[N]),
   printCCGs(L,Stream).


/*------------------------------------------------------------------------
   Build a DRS from a list of identifiers 
------------------------------------------------------------------------*/

buildList([id(_,Numbers)|L],Index,Stream):- 
   option('--ccg',true), !,
   sort(Numbers,Sorted),
   printCCGs(Sorted,Stream),
   buildList(L,Index,Stream).

buildList([id(Id,Numbers)|L],Index,Stream):- 
   sort(Numbers,Sorted),
   contextParameters(Id,[],Context),
   ccg2drs(Sorted,XDRS,Context),
   outputSem(Stream,Id,Index,XDRS), !,
   NewIndex is Index + 1,
   buildList(L,NewIndex,Stream).

buildList([_|L],Index,Stream):- !,
   buildList(L,Index,Stream).

buildList([],_,_).


/*------------------------------------------------------------------------
   Resolve a DRS from a list of IDs 
------------------------------------------------------------------------*/

resolveList([Id|L],Index,Stream):- 
   udrs2drs(Id,XDRS0),
   outputSem(Stream,Id,Index,XDRS0), !,
   NewIndex is Index + 1, 
   resolveList(L,NewIndex,Stream).

resolveList([_|L],Index,Stream):- !,
   resolveList(L,Index,Stream).

resolveList([],_,_).


/* =======================================================================
   Output Semantic Representation
========================================================================*/

outputSem(Stream,_Id,_Index,Ders):-
   option('--semantics',der), !,
   printDerList(Stream,Ders).

outputSem(Stream,Id,Index,XDRS0):-
   eqDrs(XDRS0,XDRS1),
   printSem(Stream,Id,Index,XDRS1),
   printBox(Stream,XDRS1), !,
   nl(Stream).


/* =======================================================================
   Print Derivations
========================================================================*/

printDerList(Stream,[]):- nl(Stream).

printDerList(Stream,[der(I,Der)|L]):- 
   option('--format',xml), !,
   format(Stream,'<der id="~p">~n',[I]),
   der2xml(Der,Stream),
   format(Stream,'</der>~n',[]),
   printDerList(Stream,L). 

printDerList(Stream,[der(I,Der)|L]):- 
   write(Stream,'der( '), write(Stream,I), write(Stream,', '),
   printDer(Der,Stream,_),
   write(Stream,' ).'), nl(Stream), !,
   printDerList(Stream,L). 

printDerList(Stream,[der(I,_)|L]):- 
   warning('cannot print derivation ~p',[I]),
   printDerList(Stream,L). 


/*========================================================================
   Print Derivation (bit of a hack right now!)
========================================================================*/

printDer(Comb,Stream,[Tok]):-
   Comb = t(Sem,Cat,Tok,Pos,Ne), !,
   betaConvert(Sem,Red),
   instDrs(Red), 
   write_term(Stream,t(Red,Cat,Tok,Pos,Ne),[numbervars(true),quoted(true)]).

printDer(Comb,Stream,Tok3):- 
   Comb =.. [Rule,Cat,Sem,L,R], !,
   write(Stream,Rule), 
   write(Stream,'('),
   write(Stream,Cat),
   write(Stream,','),
   betaConvert(Sem,Red),
   instDrs(Red), 
   write_term(Stream,Red,[numbervars(true),quoted(true)]),
   write(Stream,','),
   printDer(L,Stream,Tok1),
   write(Stream,','),
   printDer(R,Stream,Tok2), 
   write(Stream,')'),
   append(Tok1,Tok2,Tok3).

printDer(Comb,Stream,Tok):- 
   Comb =.. [Rule,Cat,Sem,T], !, 
   write(Stream,Rule), 
   write(Stream,'('),
   write(Stream,Cat),
   write(Stream,','),
   betaConvert(Sem,Red),
   instDrs(Red), 
   write_term(Stream,Red,[numbervars(true),quoted(true)]),
   write(Stream,','),
   printDer(T,Stream,Tok),
   write(Stream,')').

printDer(Comb,_,[]):- 
   warning('cannot print Comb ~p',[Comb]).


/* =======================================================================
   Version
========================================================================*/

version:-
   option('--version',do), !,
   version(V),
   format(user_error,'~p~n',[V]).

version.


/* =======================================================================
   Help
========================================================================*/

help:-
   option('--help',do), !,
   format(user_error,'usage: boxer [options]~n~n',[]),
   showOptions(boxer).

help:-
   option('--help',dont), !.


/* =======================================================================
   Definition of start
========================================================================*/

start:-
   current_prolog_flag(argv,[Comm|Args]),
%  set_prolog_flag(float_format,'%.20g'),
   setDefaultOptions(boxer), 
   parseOptions(boxer,Args),
   box(Comm,Args), !,
   halt.

start:- 
   error('boxer failed',[]), 
   halt.


