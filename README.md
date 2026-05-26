# Co tutaj mamy

Repozytorium zawiera opis ćwiczenia laboratoryjnego, podczas którego demonstrujemy wpływ zmienności strumienia pakietów kierowanych przez wyjściowy imnterfejs urządzenia przełączającego na opóźnienie i straty pakietów.

# Środowisko laboratoryjne

  ## Sieć

> [!Note]
> W zamyśle ćwiczenie ma zilustrować **istotę** wpływu, jaki charakterystyka ruchu pakietowego (płynny, losowy, wybuchowy/samopodobny) wywiera na metryki transferu pakietów (strata, opóźnienie, etc.). Z założenia powinno też być niskobudżetowe - realizowane z użyciem sprzętu powszechnego użytku. Dlatego konfiguracja naszego środowiska (w szczególności wielkość bufora w obserwowanym interfejsie przełącznika sieciowego) znacznie odbiega od tego, co moglibyśmy zobaczyć w rzeczywistych urządzeniach sieciowych. Ważne jest jednak, że pomimo dużych uproszczeń główny cel ćwiczenia nadal z powodzeniem daje się osiągnąć.

Środowisko laboratoryjne oparte jest na maszynach fizycznych lub wirtualnych pracujących pod systemem Linuks. Posługujemy się modelem prostej sieci emulowanej przez parę sieciowych przestrzeni nazw (ang. _newtork namespace_) reprezentujących terminale końcowe (hosty), które są dołączone do przełącznika realizowanego przez urządzenie typu _linux bridge_. Przełącznik ten modeluje ruter (urządzenie komutacji pakietów) przenoszący ruch pakietowy pomiędzy hostami. Jako generatpr ruchu pakietowego wykorzystujemy narzędzie D-ITG (jego manual jest dostępny [tutaj](https://traffic.comics.unina.it/software/ITG/manual/)). 

Schemat naszej sieci przedstawiono na poniższym rysunku. Bloki oznaczone jako `hi-s1` oraz `s1-hi` (i=1,2) to interfejsy należące do linuksowych urządzeń typu _veth pair_ (ang. _virtual eth pair_). Pary te reprezentują "kable" ethernetowe łączące poszczególne urządzenia (więcej o parach veth, a także o `linux bridge` znajdziemy w dokumentacji Linuksa oraz w innych licznych źródłach dostępnych w Internecie). W naszym przypadku strona nadawcza D-ITG (moduł `ITGSend`) działa w hoście `h1`, a w hoście `h2` działa strona odbiorcza D-ITG (moduł `ITGRecv`). Strumień ruchu generowany w `h1` przez proces `ITGSend` przepływa przez `s1` do hosta `h2` i tam jest odbierany przez proces `ITGRecv`. Proces `ITGRecv` tworzy log, na podstawie którego możemy uzyskać interesujące nas statystyki transferu pakietów. Naszym zadaniem będzie porównanie sprawności transferu pakietów dla strumieni ruchu o różnych charakterystykach. Dla podwyższenia przejrzystości eksperymentów i ułatwienia interpretacji wyników założymy przy tym, że jedynym wąskim gardłem systemu będzie interfejs `s1-h2`, który zwymiarujemy w ten sposób, aby tylko na nim uwidaczniały się niekorzystne (ale dla nas ważne) zjawiska ruchowe.   

```
       ┌───────────────────┐              ┌───────────────────┐
       │        h1         │              │        h2         │
       │    ┌─────────┐    │              │    ┌─────────┐    │
       │    │ ITGSend │    │              │    │ ITGRecv │    │
       │    └────┬────┘    │              │    └────┬────┘    │
       │         V         │              │         Λ         │
       │    ┌────┴────┐    │              │    ┌────┴────┐    │
       │    │  h1-s1  │    │              │    │  h2-s1  │    │
       └────└────┬────┘────┘              └────└────┬────┘────┘
                 │ 10.0.0.1                10.0.0.2 │
       ┌────┌────┴────┐────────────────────────┌────┴────┐────┐
       │    │  s1-h1  │                        │  s1-h2  │    │
       │    └─────────┘                        └─────────┘    │
       │                          s1                          │
       │                                                      │
       └──────────────────────────────────────────────────────┘
```

  ## Artefakty

Podstawową instrukcję do laboratorium stanowi niniejszy dokument. Dodatkowo, w pliku skryptu powłoki `lbr.sh` skomentowano szereg istotnych detali dotyczących emulowanej sieci oraz sposobu generowania ruchu pakietowego. W warstwie opisowej (komentarzy) plik należy traktować jak integralną część instrukcji o statusie Dodatku.

Jak wspomniano wyżej, środowisko laboratoryjne można skonfigurować w linuksowej maszynie fizycznej (ang. _bare metal_) lub w maszynie wirtualnej. W ramach przedmiotu TESIN studenci otrzymują obraz maszyny wirtualnej dla nadzorcy VirtualBox z zainstalowanym systemem operacyjnym Ubuntu 24.04 Desktop, skonfigurowanej z kompletem wymaganych artefaktów (zainstalowany D-ITG, dostępne wymagane skrypty _bash_ do tworzenia i do usuwania sieci). Obraz ten - o nazwie `tesin` - jest dostępny w naszym Teams. Nic nie stoi jednak na przeszkodzie, aby środowisko skonfigurować samodzielnie wg własnych upodobań (ale pod Linuksem), a same skrypty pobrać z katalogu `skrypty` w tym repozytorium.

# Ogólna forma ćwiczenia

W ramach ćwiczenia porównujemy wartości wybranych metryk jakościowych transferu pakietów w relacji `h1`-`h1` (por. wcześniejszy rysunek) dla różnych charakterystyk zmienności strumienia ruchu pakietowego w tej relacji. Ważniejsze metryki jakościowe transferu to strata pakietów, opóźnienie, _jitter_.

Podstawowe typy zmienności strumieni ruchu, które wykorzystamy, to przepływność pakietowa stała (ang. `constant packet rate`), napływ pakietów poissonowski oraz ruch typu _ON/OFF_ z założoną charakterystyką ruchu w okresach aktywności _ON_ (np. ruch typu `constant packet rate` lub poissonowski w okresie _ON_). Z wykorzystaniem narzędzia D-ITG można generować ruch także o innych własnościach niż powyżej wspomniane. Przykładowo, można generować ruch z opóźnieniem (odstępem czasowym) pomiędzy kolejnymi pakietami lub sekwencje stanów ON/OFF dla źródeł ON/OFF - opisane rozkładem Weibull'a (ruch samopodobny, całkiem dobrze modelujący ruch w rzeczywistych sieciach IP, zwłaszcza w płaszczyźnie "core", patrz np. [tutaj](https://www.sciencedirect.com/science/article/abs/pii/S1084804519301547)).

W ramach ćwiczenia realizujemy serie badań sieci, każda z nich dotyczy innego rodzaju (innej charakterystyki) strumienia ruchu, a ich wyniki końcowe wyniki są wzajemnie porównywane. Każda seria badań obejmuje pewną liczbę _eksperymentów elementarnych_ (prób), których wyniki po uśrednieniu składają się na wynik końcowy serii. Przed rozpoczęciem zasadniczej części ćwiczenia może być konieczne przeprowadzenie szeregu prób (eksperymentów elementarnych) w celu dostrojenia naszego systemu do środowiska obliczeniowego. Zwykle pracujemy w środowiskach zwirtualizowanych, na zróżnicowanym sprzęcie i może być konieczne dostosowanie pewnych parametrów naszego "systemu" (np. określenie sensownego zakresu wielkości bufora nadawczego rutera czy sensownego zakresu zmienności strumieni ruchu) do możliwości naszej platformy sprzętowo-programowej. Eksperymenty elementarne są opisane w sekcji [Eksperyment elementarny (przebieg)](#eksperyment-elementarny-przebieg), a zadania do wykonania wraz z opisem wymaganych do przeprowadzenia serii badań sieci przedstawionoo w sekcji [Zadania do wykonania](#zadania-do-wykonania).

> [!Important]
> Za realizację dodatkowego testu przy założeniu źródła o rozkładzie Weibull'a dla odstępu między kolejnymi generowanymi pakietami **zespołowi będzie przysługiwać bonus w wysokości 20%** nmominalnego _maksa_ za ćwiczenie.

> [!Note]
> Ze względu na uwarunkowania środowiska laboratoryjnego oraz rozwiązania implementacyjne generatora D-ITG poszczególne przebiegi pomiarowe (`eksperymenty elementarne`) przeprowadzane dla danego strumenia ruchu (w rozwinięciu: dla tego samego zbioru wartości parametrów opisujących zmienność generowanego strumienia ruchu) dają różne wyniki. Dla danego zbioru parametrów wymagane jest więc uśrednienie wyników zebranych co najmniej z kilku przebiegów (eksperymentów elementarnych). Dotychczasowe doświadczenia wskazują, że 10 prób pozwala uzyskać zadowalającą dokładność średniówki.

# Eksperyment elementarny (_przebieg_)

  ## Sekwencja działań 

Obsługa _elementarnego eksperymentu_ (jednego przebiegu pomiarowego) jest dość prosta. Środowisko sieciowe dla naszego eksperymentu jest tworzone z wykorzystaniem skryptu powłoki _bash_ o nazwie `lbr.sh`.

Skrypt ten zawiera szereg komentarzy wyjaśniających istotne dla nas kwestie szczegółowe. Komentarze te bezpośrednio sąsiadują z odpowiednimi komendami zawierającymi, a więc są możliwie dobrze skorelowane z warstwą "wykonawczą" skryptu. Dlatego w niniejszym dokumencie zadowalamy się opisem ogólnym, po techniczne detale odsyłając czytelników do samego skryptu.

Po wywołaniu skryptu komendą `sudo ./lbr.sh` tworzona jest sieć o topologii zilustrowanej wcześniej, a w hoście `h2` (w przestrzeni nazw sieciowych `h2`) uruchamiany jest odbiornik aplikacji D-ITG o nazwie `ITGRecv`. Odbiornik ten, na domyślnym porcie D-ITG (i na wszystkich interfejsach hosta `h2`), nasłuchuje nadchodzących pakietów generowanych przez stronę nadawczą `ITGSend`. W ramach tego skryptu nadajnik `ITGSend` NIE jest jednak uruchamiany. Skrypt `lbr.sh` wykonujemy tylko raz, na samym początku ćwiczenia.

Po wykonaniu skryptu `lbr.sh` można przystąpić do realizacji serii eksperymentów. Jeden eksperyment polega na wygenerowaniu strumienia pakietów pomiędzy `ITGSend` oraz `ITGRecv` i zarejestrowaniu jego wyników dostępnych w formie pewnych statystyk podanych w logu. W tym celu należy:

  * W **odrębnym oknie terminala** uruchomić stronę nadawczą `ITGSend`, skonfigurowaną z odpowiednimi parametrami w linii komendy (m.inn. adres strony odbiorczej, charakterystyka ruchu, czas trwania symulacji, nazwy logów nadawczego i odbiorczego i inn.). Moduł `ITGSend` uruchamiamy ręcznie w przestrzeni nazw `h1`, a przykładowa komenda ma formę (więcej o detalach parametryzacji komendy napisano w kolejnej podsekcji):

    `sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 200 -t 15000 -j 1 -l sender.log -x receiver.log -B E 100 W 10 100`

  * Po zakończeniu przebiegu należy przejrzeć logi (w szczególności log odbiorczy) i zapisać interesujące nas wyniki w celu późniejszego ich uśrednienia. Wyświetlenie logu w czytelnej formie w oknie terminala uzyskujemy komendą `/usr/bin/ITGDec <log-filename>`, gdzie `<log-filename>` to nazwa pliku z logiem (wcześniej podana w komendzie startującej generator `ITGSend`).

  W przypadku konieczności restartowania odbiornika czy wystąpienia problemów ze środowiskiem całą sieć można usunąć (w celu ponownego jej utworzenia). W tym celu korzystamy ze skryptu powłoki _clean.sh_: `sudo ./clean.sh` (komunikaty o błędach z wykonania skryptu dotyczące nieistniejących urządzeń należy zignorować).

  ## Parametryzacja strumienia ruchu (w ramach elementarnego eksperymentu)

  ### Podstawowe strumienie ruchu i przykłady

Jak już wspomniano, wykorzystujemy generator ruchu pakietowego D-ITG. Ma on dość dobry [manual (format pdf)](https://traffic.comics.unina.it/software/ITG/manual/D-ITG-2.8.1-manual.pdf), dlatego tutaj pomijamy szczegółowy opis zasad jego wykorzystania. Interesujące nas definicje/opisy zamieszczone są tam na stronie **13** (_Inter-departure time options_) i w jej okolicach. Końcowa część dokumentu zawiera przykładowe komendy dla generowania strumieni różnych typów. Dodatkowo, w naszym skrypcie `lbr.sh` (linie 209-227) znajdują się skomentowane przykłady ("działających") komend opracowanych na nasze potrzeby. Na nich powinniśmy bazować, dostosowując jedynie wartości wybranych parametrów do poszczególnych eksperymentów.

Dla typowych opisów strumieni pakietów obowiązuje też uwaga interpretacyjna dotycząca odstępu czasu między pakietami, zamieszczona na stronie **14** manuala (cyt.):

_Note:_
_- The IDT random variable provides the inter-departure time expressed in milliseconds._
_- For the sake of simplicity, in case of Constant, Uniform, Exponential and Poisson variables, each parameter, say it x, is considered as a packet rate value in packets per second. It is then internally converted to a IDT in milliseconds (y -> 1000/x)._

W odróżnieniu od powyższego (proste strumienie ruchu), w przypadku źródeł złożonych - typu ON/OFF (patrz następna podsekcja) - interpretacja parametrów zmiennych losowych opisywanych w ramach opcji `-B` (czasy trwania stanów ON i OFF) musi być zmieniona na _czas-trwania-stanu-w-milisekundach_. Przykładowo, wyrażenie `-B C 100 C 500` będzie definiować strumień o stałym czasie trwania stanu ON równym 100 ms i stałym czasie trwania stanu OFF równym 500 ms, a nie 100 lub 500 pakietów/sek; charakter napływu pakietów w stanie ON będzie wtedy opisany odrębnym parametrem, umieszczonym w głównej części komendy (czyli przed sekcją `-B`), np. `-C 1000` oznaczałoby stałą szybkość gnerowania w stanie ON równą 1000 pakietów/sek.

  ### Ruch ON/OFF

Na krótki komentarz zasługuje przypadek generowania strumieni typu ON/OFF, bo stosowny opis podany manualu może być uznany za trochę niejednoznaczny.

Z wykorzystaniem takich strumieni można generować ruch o rozkładzie czasu między kolejnymi pakietami mającym współczynnik wariancji powyżej 1, a więc "ruch wybuchowy". To wprawdzie nie zawsze oznacza ruch _samopodobny_ (ang. self-similar) w ścisłym rozumieniu tego terminu, jednak duża wariancja jest wspólną cechą tych kategorii i to jest dla nas najważniejsze.

Strumień ON/OFF można zilustrować jako sekwencję naprzemiennych odcinków czasu (stanów źródła) ON i OFF, gdy w czasie ON (aktywność źródła) źródło generuje pakiety z określoną charakterystyką strumienia, a w czasie OFF źródło w ogóle nie generuje pakietów (źródło jest nieaktywne). Zilustrowano to na rysunku poniżej.

```

              czas ON         czas OFF           czas ON
            <────────><────────────────────><────────────────> 
            ┌────────┐                      ┌────────────────┐    
            │   ON   │          OFF         │       ON       │    
        ────└────────┘──────────────────────└────────────────┘────> czas
```

Czasy trwania stanów ON i OFF mogą w ogólności być różnymi zmiennymi losowymi o odrębnych rozkładach gęstości prawdopodobieństwa. W generatorze D-ITG czasy te definiuje się z użyciem odrębnej opcji `-B` o ogólnej składni `-B <opis-czasu-ON> <opis-czasu-OFF>`, gdzie każdy ze składników `<opis-czasu-ON>` i `<opis-czasu-OFF>` można opisać stosując składnię ze strony 13 manuala, zmieniając jednak interpretację _czasu pomiędzy kolejnymi pakietami_ na, odpowiednio, _czas trwania okresów ON_ i _czas trwania okresów OFF_.

Komenda (wykorzystana w skrypcie `lbr.sh`), służąca do generowania strumieni ruchu tego rodzaju na nasze potrzeby (struktura naszej sieci itp.), ma zatem następującą formę:

```
sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 200 -t 15000 -j 1 -l sender.log -x receiver.log -B <opis-czasu-ON> <opis-czasu-OFF>
```

W naszym przypadku (tj. w naszym skrypcie `lbr.sh`) znaczenie poszczególnych fragmentów/pól jest następujące:

`-B <opis-czasu-ON> <opis-czasu-OFF>` - źródło ma być typu ON/OFF z opisem czasu trwania stanów ON/OFF podanym parametrami `<opis-czasu-ON>` i `<opis-czasu-OFF>`. Jak już wcześniej wspomniano, każdy ze składników `<opis-czasu-ON>` i `<opis-czasu-OFF>` można opisać stosując składnię ze strony 13 manuala, zmieniając tylko interpretację _czasu pomiędzy kolejnymi pakietami_ na, odpowiednio, _czas trwania okresów ON_ i _czas trwania okresów OFF_. **WAŻNE: blok `-B` - jeśli występuje - <u>musi</u> znajdować się na samym końcu komendy**; jeśli blok `B` nie występuje, wtedy komenda jest interpretowana tak, jakby czas OFF był równy zero (a źródło cały czas pozostawało w stanie ON);

`sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend` - uruchom w przestrzeni nazw sieciowych h1 (ip netns exec h1) proces aplikacji (/usr/bin/ITGSend) na możliwie wysokim priorytecie (chrt --fifo 1);

`/usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 200 -t 15000` - uruchamiana aplikacja (nasz generator ITGSend) ma słać ruch na adres 10.0.0.2, stosowć protokół UDP (-T UDP), formować pakiety o stałej długości 1500 bajtów (-c 1200) z szybkością generowania (tutaj w okresach ON, bo na końcu komendy występuje blok `-B`) równą 200 pakietów/sek (-C 200), całkowity czas trwania przebiegu ma wynosić 15000ms (czyli 15 sekund; -t 15000). Zapis `-C 200` odpowiada konkretnej charakterystyce strumienia w stanie ON (rozkład jednopunktowy) - w ogólnym przypadku może tu jednak wystąpić dowolny z rozkładów/zapisów określonych na stronie **13** manuala D-ITG (w naszym laboratorium zasadniczo posługujemy się tylko rozkładem jednopunktowym, chyba że zespół pokusi się o zadanie bonusowe z Weibull'em);

`-j 1` - dodatkowo żądamy, aby nadajnik starał sie wysyłać wszystkie teoretycznie przewidziane dla strumienia pakiety - aby utrzymać wynikającą z teorii przepływność pakietową. Za tą opcją może stać pewna słabość generatora, a trochę więcej na ten temat wyjaśniono w manualu na stronie **15**. Ostatecznie, związany z nią pewien implementacyjny detal generatora może być przyczyną obserwowanej w naszych eksperymentach nie tylko niezgodności między oczekiwaną liczbą wygenerowanych pakietów a liczbą pakietów wygenerowanych faktycznie (np. dla rozkładu _constant_ (-C)), ale także zmiennej samej liczby pakietów faktycznie wygenerowanych w kolejnych przebiegach dla ustalonego strumienia ruchu. Rozbieżność ta rośnie wraz z założoną szybkością generacji pakietów. W efekcie **wszelkie analizy i wnioski należy opierać na danych pochodzących z logów strony odbiornika `ITGRecv`**, a wyniki dla danego strumienia należy uśredniać z wielu (np. 10) przebiegów. Logów nadajnika w ogóle można nie generować. **Rezygnacja z tworzenia logu nadajnika może być tym bardziej korzystna, że dodatkowo zaoszczędzi to czas procesora i nieco poprawi ogólną jakość wyników.**

`-l sender.log -x receiver.log` - podajemy nazwy plików dla logów nadajnika i odbiornika; logi te powstają w specyficznym formacie oraz ze specyficzną zawartością i nie mają postaci czytelnej dla człowieka; czytelne, syntetyczne logi uzuskane na podstawie tych oryginalnych wyświetlamy w oknie terminala komendą `/usr/bin/ITGDec <log-filename>`

Przykładowo, konkretne wywołanie nadawcy może mieć formę:

```
sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 200 -T 15000 -j 1 -l sender.log -x receiver.log -B C 500 C 1000
```

W powyższym przykładzie specyfikujemy strumień ON/OFF o stałym czasie aktywności (stan ON) 500 ms, stałym czasie nieaktywności (stan OFF) 1000 ms, szybkości transmisji w stanie ON równej 200 pakietów/sek i stałym rozmiarze pakietu 1500 bajtów (widać, że przy całkowitym czasie trwania strumienia równym 15 sekund wykona on dziesięć cykli ON/OFF przesyłając łącznie-teoretycznie 10 * 200 * 0.5 = 1000 pakietów ze średnią przepływnością równą 1000/15=66.7 pakietów/sek).

Na podstawie powyższego opisu oraz na podstawie manuala D-ITG, dostosowanie komendy w zakresie adresacji, typu protokołu, czasu trwania przebiegu, ukształtowania rozkładu czasów trwania stanów ON/OFF innego niż stały, etc., nie powinno nastręczać trudności.

  ### Inne uwagi, przypomnienia

* Należy właściwie interpretować parametry opisujące rozkłady strumieni pakietów: strona 14 manuala, następująca uwaga:
_Note:_
_- The IDT random variable provides the inter-departure time expressed in milliseconds._
_- For the sake of simplicity, in case of Constant, Uniform, Exponential and Poisson variables, each parameter, say it x, is considered as a packet rate value in packets per second. It is then internally converted to a IDT in milliseconds (y -> 1000/x)._

* Jak już wcześniej podkreślono (także w opisie opcji `-j 1`), należy uwzględnić fakt, że wyniki przebiegów uzyskane dla danego zestawu parametrów różnią się między sobą, co pociąga konieczność realizowania serii prób (np. 10 prób) i uśredniania uzyskanych wyników.

# Dodatek: optymalizacja wydajnościowa eksperymentu

Generacja ruchu pakietowego o zadanych własnościach statystycznych nie jest trywialna w aspekcie wydajnościowym. Powodem jest konieczność wysyłania kolejnych pakietów w odstępach czasowych, które są generowane zgodnie z założonym dla danego strumienia procesem stochastycznym, utrzymując jednocześnie dużą szybkość generowania pakietów (np. emulując ruch mający dobrze dociążyć łącze 1GBit/s należy generować ok. 100 tys. pakietów na sekundę). Dla typowego sprzętu "domowego", zwłaszcza korzystając z wirtualizowanych środowisk, może to być spore wyswanie. Jast tak w szczególności w przypadku wykorzystywania aplikacji D-ITG. Z tego powodu staramy się zoptymalizować systemowe ustawienia aplikacji - zwłaszcza strony nadawczej `ITGSend` - pod kątem wydajnościowym. Pomimo tego nie udaje się uzyskać idealnych warunków pracy generatora. Dotyczy to w szczególności rozbieżności pomiędzy zakładaną (teoretyczną) a faktycznie wygenerowaną w założonym czasie liczbą pakietów. Dlatego wnioski należy ostatecznie "kalibrować" względem wartości faktycznie uzyskanych, a nie teoretycznie wynikających z przyjętych ustawień; o kalibracji więcej napisano w sekcji [Zadania do wykonania](#zadania-do-wykonania).

  ## Maszyna goszcząca i maszyna wirtualna

  Zalecane jest wyłączenie zbędnych aplikacji w maszynie goszczącej, które okresowo "zjadają" zasoby CPU. W szczególności dotyczy to przeglądarek. Niestety, przynajmniej w Windows, nie da się zmienić priorytetu procesów danej VM dla nadzorcy VirtualBox. Pewne sposoby podwyższania priorytetu VM są dostępne w Hyper-V, ale (pomijając nawet kwestię innego obrazu) nie jest to trywialne i rezygnujemy z tego zabiegu w naszym przypadku.

  ## Moduł odbiorczy `ITGRecv`

Moduł ten jest uruchamiany z domyślnym dla Linuksa priorytetem procesu (parametr `nice` równy zero, niczego nie trzeba specyfikować w linii komendy - porównaj skrypt `lbr.sh`).

  ## Moduł nadawczy `ITGSend`

Moduł nadawczy jest uruchamiany z możliwie wysokim priorytetem procesu (parametr `chrt --fifo 1` w linii komendy - por. skrypt `lbr.sh`). Dodatkowo, zgodnie z podanym wcześniej opisem (i komentarzem w manualu D-ITG) dotyczącym opcji `-j 1`, można zrezygnować z generowania logów po stronie nadawczej (w naszej komendzie uruchamiajacej nadawcę `ITGSend` wystarczy usunąć opcję `-l sender.log`).

# Zadania do wykonania

W ćwiczeniu zakładamy stały rozmiar pakietu. Generator D-ITG pozwala na losowy rozmiar pakietów, ale to dodatkowo obciąża procesor, czego w naszym srodowisku wolimy unikać.

Należy ustalić ogólny punkt pracy sieci dla swojego środowiska. Definiują go następujące parametry:

* przepływność łącza `s1-h2`
* wielkość bufora (w założeniu nadawczego) dla interfejsu `s1-h2`; na tym łączu będzie koncentrować się ruch w kierunku hosta `h2` i tutaj będziemy obserwować proces buforowania i utraty pakietów (w naszym skrypcie pozostałe interfejsy są wymiarowane na "maksa", aby nie wpływały na wyniki eksperymentów)
* rozmiar pakietu: przyjętą w skrypcie `lbr.sh` wartość 1200 bajtów można uznać za właściwą i korygować tylko w uzasadnionych przypadkach

W skrypcie `lbr.sh` parametry interfejsu `s1-h2` ustalane są bufora ustalają punkt pracy 

Z perspektywy zewnętrznego obserwatora postrzegany współczynnik wariancji przepływności pakietowej dla strumienia pakietów typu ON/OFF w naszym przypadku (zakładamy stałe czasy trwania stanów ON/OFF równe, odpowiednio, _t<sub>on</sub>_ i _t<sub>off</sub>_, oraz stałą przepływność pakietową w stanie ON) określony jest wzorem (warto to samodzielnie sprawdzić):

$$
CV = \frac{\sqrt{t_{off} \cdot (t_{on} + t_{off})}}{t_{on}}
$$

Można zauważyć, że dla powyższego przypadku, przy zależności _t<sub>on</sub>=1.618 t<sub>off</sub>_, współczynnik wariancji obserwowanej przepływności pakietowej przyjmuje wartość 1. Spodziewamy się, że dla źródeł ON/OFF warto skalować nasz eksperyment z czasami _t<sub>on</sub>_ proporcjonalnie krótszymi niż w tej zależności (czyli o współczynniku proporcjonalności względem _t<sub>off</sub>_ poniżej wartości 1.618).
