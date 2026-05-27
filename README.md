# Co tutaj mamy

Repozytorium zawiera opis ćwiczenia laboratoryjnego, podczas którego demonstrujemy wpływ zmienności strumienia pakietów (dokładniej, zmian intensywności strumienia pakietów) wychodzących przez interfejs urządzenia przełączającego na opóźnienie i straty pakietów na tym interfejsie. Celem ćwiczenia jest ugruntowanie wiedzy dotyczącej zjawisk ruchowych zachodzących w sieciach pakietowych, a przy okazji zapoznanie się z przykładowymi narzędziami pomocnymi w analizie tych zjawisk.

> [!Note]
> Wyjaśnienie: w podstawowej wersji laboratorium nie generujemy ruchu samopodobnego (self-similar czy long-range dependent) w ścisłym rozumieniu, a jedynie ruch ON/OFF o współczynniku wariancji większym od 1. Zainteresowani użytkownicy mogą jednak w ramach prac własnych samodzielnie skonfigurować stronę nadawczą narzędzia D-ITG w celu emulowania strumieni bardziej zbliżonych do samopodobnych. W tym celu można użyć np. rozkładu Weibull'a dla generowania czasów trwania stanów ON/OFF źródeł binarnych czy czasu między kolejnymi pakietami w stanie aktywnym źródła ruchu.

# Spis treści

1. [Środowisko laboratoryjne](#środowisko-laboratoryjne)
   1. [Sieć](#sieć)
   2. [Artefakty](#artefakty)
2. [Ogólna forma ćwiczenia](#ogólna-forma-ćwiczenia)
3. [Pomiar elementarny](#pomiar-elementarny-przebieg)
   1. [Sekwencja działań](#sekwencja-działań)
   2. [Parametryzacja strumienia ruchu (w ramach elementarnego pomiaru)](#parametryzacja-strumienia-ruchu-w-ramach-elementarnego-pomiaru)
      1. [Podstawowe strumienie ruchu i przykłady użycia](#podstawowe-strumienie-ruchu-i-przykłady-użycia)
      2. [Przypadek złożony: ruch ON/OFF](#przypadek-złożony-ruch-onoff)
      3. [Inne uwagi, przyomnienia](#inne-uwagi-przypomnienia)
4. [Opis zadań do wykonania](#opis-zadań-do-wykonania)
   1. [Ustalenie właściwego punktu pracy sieci](#ustalenie-właściwego-punktu-pracy-sieci)
   2. [Ćwiczenie właściwe](#ćwiczenie-właściwe)
      1. [Parametry: ustawienia](#parametry-ustawienia)
      2. [Seria pomiarów](#seria-pomiarów)
   3. [Raport: wyniki i wnioski](#raport-wyniki-i-wnioski)
5. [DODATEK: optymalizacja wydajnościowa pomiarów](#dodatek-optymalizacja-wydajnościowa-pomiarów)
   1. [Maszyna goszcząca i maszyna wirtualna](#maszyna-goszcząca-i-maszyna-wirtualna)
   2. [Moduł odbiorczy ITGRecv](#moduł-odbiorczy-itgrecv)
   3. [Moduł nadawczy ITGSend](#moduł-nadawczy-itgsend)

# Środowisko laboratoryjne

  ## Sieć

> [!Note]
> W zamyśle ćwiczenie ma zilustrować **istotę** wpływu, jaki charakterystyka ruchu pakietowego (płynny, losowy, wybuchowy/samopodobny) wywiera na metryki transferu pakietów (strata, opóźnienie, etc.). Z założenia ćwiczenie powinno też być niskobudżetowe - realizowane z użyciem sprzętu powszechnego użytku. Dlatego "ilościowa" konfiguracja naszego środowiska (w szczególności rozmiar bufora w obserwowanym interfejsie przełącznika sieciowego) znacznie odbiega od tego, co moglibyśmy zobaczyć w urządzeniach rzeczywistej sieci. Ważne jest jednak, że pomimo dużych ograniczeń i uproszczeń główny cel ćwiczenia nadal z powodzeniem daje się osiągnąć.

Środowisko laboratoryjne oparte jest na maszynach fizycznych lub wirtualnych pracujących pod systemem Linuks. Posługujemy się modelem prostej sieci emulowanej przez parę sieciowych przestrzeni nazw (ang. _newtork namespace_) reprezentujących terminale końcowe (hosty), które są dołączone do przełącznika realizowanego przez urządzenie typu _linux bridge_. Przełącznik ten modeluje ruter przenoszący ruch pakietowy pomiędzy hostami. Jako generator ruchu pakietowego wykorzystujemy narzędzie D-ITG (jego manual jest dostępny [tutaj](https://traffic.comics.unina.it/software/ITG/manual/)). Składa się nań kilka modułów-aplikacji służących różnym celom. W laboratorium używamy (właściwego) generatora ruchu `ITGSend`, odbiornika ruchu `ITGRecv` oraz dekodera logów `ITGDec`.

Schemat naszej sieci przedstawiono na poniższym rysunku. Bloki oznaczone jako `hi-s1` oraz `s1-hi` (i=1,2) to interfejsy należące do linuksowych urządzeń typu _veth pair_ (ang. _virtual eth pair_). Pary te reprezentują "kable" ethernetowe łączące poszczególne urządzenia (więcej o parach veth, a także o `linux bridge` znajdziemy w dokumentacji Linuksa oraz w innych licznych źródłach dostępnych w Internecie).

```
       ┌───────────────────┐              ┌───────────────────┐
       │        h1         │              │        h2         │
       │    ┌─────────┐    │              │    ┌─────────┐    │
       │    │ ITGSend │    │              │    │ ITGRecv │    │
       │    └────┬────┘    │              │    └────┬────┘    │
       │     UDP V         │              │     UDP Λ         │
       │    ┌────┴────┐    │              │    ┌────┴────┐    │
       │    │  h1-s1  │10.0.0.1           │    │  h2-s1  │10.0.0.2
       └────└────┬────┘────┘              └────└────┬────┘────┘
                 │                                  │
       ┌────┌────┴────┐────────────────────────┌────┴────┐────┐
       │    │  s1-h1  │                        │  s1-h2  │    │
       │    └─────────┘                        └─────────┘    │
       │                          s1         konfigurowane tc │
       │                                                      │
       └──────────────────────────────────────────────────────┘
```

W naszym przypadku strona nadawcza D-ITG (moduł `ITGSend`) działa w hoście `h1`, a w hoście `h2` działa strona odbiorcza D-ITG (moduł `ITGRecv`). Strumień ruchu generowany w `h1` przez proces `ITGSend` przepływa przez `s1` do hosta `h2` i tam jest odbierany przez proces `ITGRecv`. Proces `ITGRecv` tworzy log, na podstawie którego możemy uzyskać interesujące nas statystyki transferu pakietów. Naszym zadaniem będzie porównanie sprawności transferu pakietów dla strumieni ruchu o różnych charakterystykach. Dla podwyższenia przejrzystości pomiarów i ułatwienia interpretacji wyników założymy przy tym, że jedynym wąskim gardłem systemu będzie interfejs `s1-h2`, który zwymiarujemy w ten sposób, aby tylko na nim uwidaczniały się niekorzystne (ale dla nas ważne) zjawiska ruchowe.

  ## Artefakty

Niniejszy dokument jest podstawową instrukcją do laboratorium. Dodatkowo, w pliku skryptu powłoki `lbr.sh` skomentowano szereg istotnych detali dotyczących emulowanej sieci oraz sposobu generowania ruchu pakietowego. W warstwie opisowej (komentarzy) plik należy traktować jak integralną część instrukcji o statusie Dodatku.

Jak wspomniano wcześniej, środowisko laboratoryjne można skonfigurować w linuksowej maszynie fizycznej (ang. _bare metal_) lub w maszynie wirtualnej. W ramach przedmiotu TESIN studenci otrzymują kompletny obraz maszyny wirtualnej dla nadzorcy VirtualBox z zainstalowanym systemem operacyjnym Ubuntu 24.04 Desktop i dodatkami VBoxGuestAdditions, skonfigurowanej z kompletem wymaganych artefaktów (zainstalowany D-ITG, dostępne wymagane skrypty _bash_ do tworzenia i do usuwania sieci). Obraz ten - o nazwie `tesin` - jest dostępny w naszym Teams. Artefakty są dostępne na koncie użytkownika `student` w katalogu `~/Labs/traffic`. Nic nie stoi jednak na przeszkodzie, aby środowisko skonfigurować samodzielnie wg własnych upodobań (ale nadal pod Linuksem), a same skrypty pobrać z katalogu `skrypty` zamieszczone w niniejszym repozytorium (Uwaga: w przypadku korzystania z innej dystrybucji Linuksa niż Ubuntu może być konieczne zbudowanie wersji binarnej D-ITG ze źródeł - wg opisu dostępnego [tutaj](https://github.com/jbucar/ditg/blob/master/INSTALL.)).

# Ogólna forma ćwiczenia

W ramach ćwiczenia porównujemy wartości wybranych metryk jakościowych transferu pakietów w relacji `h1`-`h1` (por. wcześniejszy rysunek) dla różnych charakterystyk zmienności strumienia ruchu pakietowego w tej relacji. Ważniejsze metryki jakościowe transferu to strata pakietów, opóźnienie, _jitter_.

Podstawowe typy zmienności strumieni ruchu, które wykorzystamy, to przepływność pakietowa stała (ang. `constant packet rate`), napływ pakietów poissonowski oraz ruch typu _ON/OFF_ z założoną charakterystyką ruchu w okresach aktywności _ON_ (np. ruch typu `constant packet rate` lub poissonowski w okresie _ON_). Z wykorzystaniem narzędzia D-ITG można generować ruch także o innych własnościach niż powyżej wspomniane. Przykładowo, można generować ruch z opóźnieniem (odstępem czasowym) pomiędzy kolejnymi pakietami lub sekwencje stanów ON/OFF dla źródeł ON/OFF - opisane rozkładem Weibull'a (ruch samopodobny, całkiem dobrze modelujący ruch w rzeczywistych sieciach IP, zwłaszcza w płaszczyźnie "core", patrz np. [tutaj](https://www.sciencedirect.com/science/article/abs/pii/S1084804519301547)).

W ramach ćwiczenia realizujemy serie pomiarów sieci, każda z nich dotyczy innego rodzaju (innej charakterystyki) strumienia ruchu, a ich wyniki końcowe wyniki są wzajemnie porównywane. Każda seria pomiarów obejmuje pewną liczbę _pomiarów elementarnych_ (prób), których wyniki po uśrednieniu składają się na wynik końcowy serii. Przed rozpoczęciem właściwej części ćwiczenia może być konieczne przeprowadzenie szeregu prób (pomiarów elementarnych) w celu dostrojenia naszego systemu do środowiska obliczeniowego. Zwykle pracujemy w środowiskach zwirtualizowanych, na zróżnicowanym sprzęcie i może być konieczne dostosowanie pewnych parametrów naszego "systemu" (np. określenie sensownego zakresu wielkości bufora nadawczego rutera czy sensownego zakresu zmienności strumieni ruchu) do możliwości naszej platformy sprzętowo-programowej. pomiary elementarne są opisane w sekcji [pomiar elementarny (przebieg)](#pomiar-elementarny-przebieg), a zadania do wykonania wraz z opisem wymaganych do przeprowadzenia serii pomiarów sieci przedstawiono w sekcji [Opis zadań do wykonania](#opis-zadań-do-wykonania).

> [!Important]
> Za realizację dodatkowego testu przy założeniu źródła o rozkładzie Weibull'a dla odstępu między kolejnymi generowanymi pakietami **zespołowi będzie przysługiwać bonus w wysokości 20%** nmominalnego _maksa_ za ćwiczenie.

> [!Note]
> Ze względu na uwarunkowania środowiska laboratoryjnego oraz rozwiązania implementacyjne generatora D-ITG poszczególne przebiegi pomiarowe (`pomiary elementarne`) przeprowadzane dla danego strumenia ruchu (w rozwinięciu: dla tego samego zbioru wartości parametrów opisujących zmienność generowanego strumienia ruchu) dają różne wyniki. Dla danego zbioru parametrów wymagane jest więc uśrednienie wyników zebranych co najmniej z kilku przebiegów (pomiarów elementarnych). Dotychczasowe doświadczenia wskazują, że 10 prób pozwala uzyskać zadowalającą dokładność średniówki.

# Pomiar elementarny (_przebieg_)

  ## Sekwencja działań 

Obsługa _elementarnego pomiaru_ (jednego przebiegu pomiarowego) jest dość prosta. Środowisko sieciowe dla naszego pomiaru jest tworzone z wykorzystaniem skryptu powłoki _bash_ o nazwie `lbr.sh`.

Skrypt ten zawiera szereg komentarzy wyjaśniających istotne dla nas kwestie szczegółowe. Komentarze te bezpośrednio sąsiadują z odpowiednimi komendami zawierającymi, a więc są możliwie dobrze skorelowane z warstwą "wykonawczą" skryptu. Dlatego w niniejszym dokumencie zadowalamy się opisem ogólnym, po techniczne detale odsyłając czytelników do samego skryptu.

Po wywołaniu skryptu komendą `sudo ./lbr.sh` tworzona jest sieć o topologii zilustrowanej wcześniej, a w hoście `h2` (w przestrzeni nazw sieciowych `h2`) uruchamiany jest odbiornik aplikacji D-ITG o nazwie `ITGRecv`. Odbiornik ten, na domyślnym porcie D-ITG (i na wszystkich interfejsach hosta `h2`), nasłuchuje nadchodzących pakietów generowanych przez stronę nadawczą `ITGSend`. W ramach tego skryptu nadajnik `ITGSend` NIE jest jednak uruchamiany. Skrypt `lbr.sh` wykonujemy tylko raz, na samym początku ćwiczenia.

Po wykonaniu skryptu `lbr.sh` można przystąpić do realizacji kolejnych pomiarów. Jeden pomiar polega na wygenerowaniu strumienia pakietów pomiędzy `ITGSend` oraz `ITGRecv` i zarejestrowaniu jego wyników dostępnych w formie pewnych statystyk podanych w logu. W tym celu należy:

  * W **odrębnym oknie terminala** uruchomić stronę nadawczą `ITGSend`, skonfigurowaną z odpowiednimi parametrami w linii komendy (m.inn. adres strony odbiorczej, charakterystyka ruchu, czas trwania symulacji, nazwy logów nadawczego i odbiorczego i inn.). Moduł `ITGSend` uruchamiamy ręcznie w przestrzeni nazw `h1`, a przykładowa komenda ma formę (więcej o detalach parametryzacji komendy napisano w kolejnej podsekcji):

    `sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 200 -t 15000 -j 1 -l sender.log -x receiver.log -B E 100 W 10 100`

  * Po zakończeniu przebiegu należy przejrzeć logi (w szczególności log odbiorczy) i zapisać interesujące nas wyniki w celu późniejszego ich uśrednienia. Wyświetlenie logu w czytelnej formie w oknie terminala uzyskujemy komendą `/usr/bin/ITGDec <log-filename>`, gdzie `<log-filename>` to nazwa pliku z logiem (wcześniej podana w komendzie startującej generator `ITGSend`).

  W przypadku konieczności restartowania odbiornika czy wystąpienia problemów ze środowiskiem całą sieć można usunąć (w celu ponownego jej utworzenia). W tym celu korzystamy ze skryptu powłoki _clean.sh_: `sudo ./clean.sh` (komunikaty o błędach z wykonania skryptu dotyczące nieistniejących urządzeń należy zignorować).

  ## Parametryzacja strumienia ruchu (w ramach elementarnego pomiaru)

  ### Podstawowe strumienie ruchu i przykłady użycia

Jak już wspomniano, wykorzystujemy generator ruchu pakietowego D-ITG. Ma on dość dobry [manual (format pdf)](https://traffic.comics.unina.it/software/ITG/manual/D-ITG-2.8.1-manual.pdf), dlatego tutaj pomijamy szczegółowy opis zasad jego wykorzystania. Interesujące nas definicje/opisy zamieszczone są tam na stronie **13** (_Inter-departure time options_) i w jej okolicach. Końcowa część dokumentu zawiera przykładowe komendy dla generowania strumieni różnych typów. Dodatkowo, w naszym skrypcie `lbr.sh` (linie 218-251) znajdują się skomentowane przykłady ("działających") komend opracowanych na nasze potrzeby. Na nich powinniśmy bazować, dostosowując jedynie wartości wybranych parametrów do poszczególnych pomiarów.

Dla typowych opisów strumieni pakietów obowiązuje też uwaga interpretacyjna dotycząca odstępu czasu między pakietami, zamieszczona na stronie **14** manuala (cyt.):

_Note:_
_- The IDT random variable provides the inter-departure time expressed in milliseconds._
_- For the sake of simplicity, in case of Constant, Uniform, Exponential and Poisson variables, each parameter, say it x, is considered as a packet rate value in packets per second. It is then internally converted to a IDT in milliseconds (y -> 1000/x)._

W odróżnieniu od powyższego (proste strumienie ruchu), w przypadku źródeł złożonych - typu ON/OFF (patrz następna podsekcja) - interpretacja parametrów zmiennych losowych opisywanych w ramach opcji `-B` (czasy trwania stanów ON i OFF) musi być zmieniona na _czas-trwania-stanu-w-milisekundach_. Przykładowo, wyrażenie `-B C 100 C 500` będzie definiować strumień o stałym czasie trwania stanu ON równym 100 ms i stałym czasie trwania stanu OFF równym 500 ms, a nie 100 lub 500 pakietów/sek; charakter napływu pakietów w stanie ON będzie wtedy opisany odrębnym parametrem, umieszczonym w głównej części komendy (czyli przed sekcją `-B`), np. `-C 1000` oznaczałoby stałą szybkość gnerowania w stanie ON równą 1000 pakietów/sek.

  ### Przypadek złożony: ruch ON/OFF

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

`-j 1` - dodatkowo żądamy, aby nadajnik starał sie wysyłać wszystkie teoretycznie przewidziane dla strumienia pakiety - aby utrzymać wynikającą z teorii przepływność pakietową. Za tą opcją może stać pewna słabość generatora, a trochę więcej na ten temat wyjaśniono w manualu na stronie **15**. Ostatecznie, związany z nią pewien implementacyjny detal generatora może być przyczyną obserwowanej w naszych pomiarach nie tylko niezgodności między oczekiwaną liczbą wygenerowanych pakietów a liczbą pakietów wygenerowanych faktycznie (np. dla rozkładu _constant_ (-C)), ale także zmiennej samej liczby pakietów faktycznie wygenerowanych w kolejnych przebiegach dla ustalonego strumienia ruchu. Rozbieżność ta rośnie wraz z założoną szybkością generacji pakietów. W efekcie **wszelkie analizy i wnioski należy opierać na danych pochodzących z logów strony odbiornika `ITGRecv`**, a wyniki dla danego strumienia należy uśredniać z wielu (np. 10) przebiegów. Logów nadajnika w ogóle można nie generować. **Rezygnacja z tworzenia logu nadajnika może być tym bardziej korzystna, że dodatkowo zaoszczędzi to czas procesora i nieco poprawi ogólną jakość wyników.**

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

* Jak już wcześniej podkreślono (także w opisie opcji `-j 1`), należy uwzględnić fakt, że wyniki przebiegów uzyskane dla danego zestawu parametrów różnią się między sobą, co pociąga konieczność realizowania szeregu pomiarów (np. 10 prób) i uśredniania uzyskanych wyników.

# Opis zadań do wykonania

W ćwiczeniu zakładamy stały rozmiar pakietu. Generator D-ITG pozwala wprawdzie generować pakiety o losowym rozmiarze określonym różnymi rozkładami, ale to dodatkowo obciąża procesor, czego w naszym przypadku wolimy unikać.

Ogólny tok postępowania obejmuje 

## Ustalenie właściwego punktu pracy sieci

Na wstępie nleży ustalić ogólny punkt pracy sieci dla swojego środowiska. Definiują go następujące parametry:

* przepływność łącza `s1-h2`
* rozmiar bufora (w założeniu nadawczego) dla interfejsu `s1-h2`; na tym interfejsie będzie koncentrować się ruch w kierunku hosta `h2` i tutaj pakiety będą doświadczać większych opóźnień i odrzucania (w naszym skrypcie pozostałe interfejsy są wymiarowane na "maksa", aby nie wpływały na wyniki pomiarów)
* rozmiar pakietu: przyjętą w skrypcie `lbr.sh` wartość 1200 bajtów można uznać za właściwą i korygować tylko w uzasadnionych przypadkach

Właściwą przepływność łącza `s1-h2` i rozmiar bufora dla interfejsu `s1-h2` ustalamy następująco.

W skrypcie `lbr.sh` parametry te są konfigurowane w linii 187 z użyciem narzędzia `tc` (manual jest dostępny [tutaj](https://man7.org/linux/man-pages/man8/tc.8.html)). W naszym skrypcie komenda ta wygląda następująco:

```
tc qdisc add dev s1-h2 root netem rate 1.2mbit limit 10`
```
Konfiguruje ona przepływność łącza równą 1.2 Mbit/s oraz rozmiar bufora nadawczego równy 10 pakietów. To wartości bardzo skromne w porównaniu z prawdziwym sprzętem sieciowym, ale wystarczające do zilustrowania interesujących nas zjawisk w naszym wymagającym środowisku obliczeniowym. Podane tu konkretne wartości należy jednak traktować orientacyjnie. Zadaniem zespołu jest wstępne rozeznanie, czy na potrzeby prowadzenia pomiarów w jego środowisku nie należałoby tych wartości zmodyfikować.

W tym celu należy przeprowadzić pewną liczbę wstępnych pomiarów elementarnych. Na tym etapie, metodą prób i błędów, należy zmieniać przepływność i rozmiar bufora (czyli wielokrotnie usuwać sieć i tworzyć nową jej wersję), a dla każdej nowej wersji sieci sprawdzać straty pakietów dla strumieni typu _constant packet rate_ (opcja `-C`) przy różnych wartościach `X` szybkości tramsmisji: opcja `-C X`. Wykorzystywana w tym celu komenda generatora `ITGSend` powinna mieć postać (zaczerpniętą zresztą ze skryptu `lbr.sh`) jak poniżej, z zastrzeżeniem, że pole oznaczone jako `X` to właśnie modyfikowana przez nas szybkość transmisji nadajnika w [pakiety/sek]:

```
sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C X -t 15000 -j 1 -l sender.log -x receiver.log
```

Startujemy z parametrami łącza `s1-h2` w formie `rate 1.2mbit limit 10` i wartością `X` równą 100 (pakietów/sek). Starmy się podwyższać przepływność łącza i rozmiar bufora, a dla konkretnych nastaw dla łącza - podwyższać `X` tak, aby

* w logu odbiornika zaczęły pojawiać się niezerowe straty pakietów (log odbiornika sprawdzamy komendą `/usr/bin/ITGDec receiver.log`),
* A JEDNOCZEŚNIE liczba faktycznie wygenerowanych pakietów nie była zbyt mała w stosunku do wartości teoretycznej (np. nie spadła poniżej 75% wartości teoretycznej). Wartość faktyczna (osiągnięta) na podstawie logu odbiornika to suma pól _Total packets_ i _Packets dropped_ (por opis w skrypcie `lbr.sh`); natomiast wartość teoretyczna to iloczyn wartości parametrów komendy `-C` i `-t` podzielony przez `1000`: $Ct/1000$. Kończymy poszukiwania kiedy uznamy, że nasze (wprawdzie dość miękkie) ograniczenia zostały wyczerpane. Log odbiornika na następujący wygląd - widać tu pola wymienione powyżej (komentarz _kursywą_ jest mój):

<pre>-----------------------------------------------------------
---
<i>Uwaga DB: log został uzyskany dla łącza o nastawach rate 1.2mbit limit 10 oraz komendy generatora
sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 150 -t 15000 -j 1 -l sender.log -x receiver.log
Jak widać, teoretycznie powinno zostać wygenerowanych 2250 pakietów, a faktycznie wygenerowano ich 2071. Taka rozbieżność jest naszym zdaniem akceptowalna - sieć można byłoby nawet jeszcze odrobinę "podkręcić".</i>
---
Flow number: 1
From 10.0.0.1:46291
To    10.0.0.2:8999
----------------------------------------------------------
Total time               =     15.069208 s
Total packets            =          1819
Minimum delay            =      0.009084 s
Maximum delay            =      0.110507 s
Average delay            =      0.076653 s
Average jitter           =      0.001990 s
Delay standard deviation =      0.012643 s
Bytes received           =       2182800
Average bitrate          =   1158.813390 Kbit/s
Average packet rate      =    120.709728 pkt/s
Packets dropped          =           252 (12.17 %)
Average loss-burst size  =      1.000000 pkt
----------------------------------------------------------</pre>

**Komentarz końcowy:** W istocie chcielibyśmy prowadzić pomiary łączy o dużych przepływnościach i dużych buforach, i przyu wysokich szybkościach generowania pakietów przez nadajnik `ITGSend`. Lepiej oddawałoby to realne warunki pracy ruterów w sieciach. Jak widać powyżej, w naszym przypadku musimy jednak pogodzić się z niskimi wartościami tych parametrów. Powyższa procedura wskazuje tylko, w jaki sposób można spróbować je nieco zwiększyć względem nastaw domyślnych (zaczerpniętych ze skryptu `lbr.sh`).

## Ćwiczenie właściwe

To główny etap realizacji laboratorium.

Zgodnie z wcześniejszym komentarzem, etap ten obejmuje kilka _serii pomiarów_ sieci, a każda z nich dotyczy określonego typu (innej charakterystyki) strumienia ruchu pakietowego. W podstawowej wersji laboratorium badamy trzy typy strumieni: strumień _constant packet rate_ (parametr definiujący w komendzie ITGSend `-C`), strumień Poissona (parametr definiujący w komendzie ITGSend `-P`) oraz strumień ON/OFF (parametr definiujący w komendzie ITGSend `-B` umieszczony na końcu komendy). Ostatecznym wynikiem jednej _serii pomiarów_ jest - obrazowo to ujmując - wykres (lub wykresy) przedstawiający eksperymentalnie wyznaczony przebieg opóźnienia i straty pakietów w funkcji szybkości napływu pakietów dla określonego typu strumienia ruchu pakietowego. Wyniki końcowe wszystkich _serii pomiarów_ podlegają analizie przez zespół laboratoryjny i na tej podstawie formułowane są wnioski końcowe.

Każda _seria pomiarów_ obejmuje pewną liczbę _punktowych serii pomiarowych_, gdzie każda punktowa seria pomiarowa służy do oszacowania wartości interesujących nas metryk (opóźnienia i straty pakietów) dla <u>zadanej</u> szybkości generowania pakietów. Zestaw wielu punktowych serii pomiarowych (każda dla innej szybkości generowania pakietów) pozwala wykreślić graficzną zależność naszych metryk w funkcji szybkości napływu (generowania) pakietów. Punktowa seria pomiarowa obejmuje natomiast szereg (np. 10) _pomiarów elementarnych_ (wszystkie przeprowadzone dla ustalonych parametrów strumienia), których uśrednione wyniki stanowią końcowy rezultat danej _punktowej serii pomiarowej_.

W kolejnych dwóch podsekcjach przedstawiamy, odpowiednio, zasady parametryzacji pomiarów oraz sposób realizacji jednej _serii pomiarów_. Realizacja takiej serii dla każdego z interesujących nas typów strumienia ruchu pakietowego wypełnia "operacyjną" część laboratorium. Jest ona podstawą do analizy i sformułowania wniosków końcowych.

### Parametry: ustawienia

Ustaliwszy [właściwy punkt pracy sieci](#ustalenie-właściwego-punktu-pracy-sieci) jesteśmy przygotowani do przeprowadzenia docelowych badań. Zbierzmy w jednym miejscu nasze główne założenia. Cześć z nich dotyczy do wszystkich badań, a część tylko badań poświęconym ruchowi typu ON/OFF. Poniżej przedstawiamy je w dwóch odpowiednich grupach.

* parametry wspólne

Dla wszystkich serii pomiarów stosujemy protokół UDP (parametr `-T UDP`), ten sam rozmiar pakietu (parametr `-c`) oraz czas trwania próby (parametr `-t`). Oczywiście ustawienia interfejsu `s1-h2` z poprzedniej podsekcji również mają być wspólne dla wszystkich serii pomiarów.  

* źródło ruchu ON/OFF

W naszym przypadku zakładamy stałe czasy trwania stanów ON/OFF równe, odpowiednio, _t<sub>on</sub>_ i _t<sub>off</sub>_, oraz stałą przepływność pakietową w stanie ON. Wtedy, z perspektywy zewnętrznego obserwatora współczynnik wariancji obserwowanej chwilowej przepływności pakietowej dla takiego strumienia jest określony wzorem (warto to samodzielnie sprawdzić):

$$
CV = \frac{\sqrt{t_{off} \cdot (t_{on} + t_{off})}}{t_{on}}
$$

Można zauważyć, że dla powyższego przypadku, przy zależności $t_{on}=1.618 \cdot t_{off}$, współczynnik wariancji obserwowanej chwilowej przepływności pakietowej przyjmuje wartość 1. Spodziewamy się, że dla źródeł ON/OFF warto skalować nasz pomiar z czasami _t<sub>on</sub>_ proporcjonalnie krótszymi względem _t<sub>off</sub>_ niż w tej zależności (czyli o wartościach współczynnika proporcjonalności względem _t<sub>off</sub>_ poniżej 1.618).

### Seria pomiarów

Przyjmując ustalenia z [poprzedniej podsekcji](#parametry-ustawienia) serię pomiarów organizujemy następująco:

* Ustalenie zakresu pomiarowego na osi odciętych - zakresu szybkości generowania pakietów przez aplikację `ITGSend` (prościej, jest to zakres zmian dla osi odciętych). Zasadniczo, **krok ten realizujemy tylko przed przystąpieniem do pierwszej serii pomiarów**. Jeśli seria jest realizowana jako kolejna, wówczas krok ten pomijamy (z zastrzeżeniem możliwości rozszerzenia zakresu w uzasadnionych przypadkach). Zakres ten powinien być na tyle szeroki, aby dla większych szybkości generowania pakietów z tego zakresu występowały zauważalne (np. 5-10%), a dla największych duże (np. 30-50%) straty pakietów. Oczywiście zakres ten można będzie później zmienić, na przykład rozszerzyć i dorobić brakujące pomiary, ale dobrze jest już na wstępie oszacować obszar działań, aby lepiej rozłożyć _punkty pomiarowe_ na osi odciętych (punkt pomiarowy to oczekiwana osiągana szybkość generowania pakietów przez źródło). Liczba punktów pomiarowych z przedziału 7-10 wydaje się wystarczająca w naszym przypadku; zważywszy na kolejkowy chrakter obserwowanych procesów lepiej jest zagęszczać punkty pomiarowe w kierunku rosnących wartości na osi odciętych. Kluczowa jest tutaj właściwa interpretacja terminu "oczekiwana osiągana szybkość generowania pakietów przez źródło", dlatego jeszcze raz przypominamy: to szybkość wyliczona na podstawie liczby pakietów faktycznie zarejestrowanych w logu odbiorcy `ITGRecv`, wyliczana jako $`(Total\char`_packets + Packets\char`_dropped) / 1000`$. 
* W tak ustalonym zakresie pomiarowym wybieramy _punkty pomiarowe odniesienia_ (szybkości generowania pakietów mające faktycznie być osiągnięte - przynajmniej z przybliżeniem - jako wartości odniesienia).
* Dla każdego z wyznaczonych punktów pomiarowych odniesienia przeprowadzamy pewną liczbę wstępnych [pomiarów elementarnych](#pomiar-elementarny-przebieg) zmieniając **teoretyczną** szybkość generowania pakietów `X` (w parametrach `-C X` czy `-O X`) tak, aby ostatecznie wartość średnia wyrażenia $(Total{\_}packets + Packets{\_}dropped) / 1000$ z kilku takich pomiarów, przeprowadzonych dla ustalonej wartości `X`, z dobrym przybliżeniem odpowiadała zakładanemu punktowi pomiarowemu odniesienia. W uproszczeniu, metodą prób i błędów wyszukujemy taką wartość `X`, dla której faktycznie osiągana szybkość generowania pakietów (dokładniej: jej wartość uśredniona z kilku przebiegów) z grubsza odpowiada bieżącemu punktowi pomiarowemu odniesienia. Wartość faktycznie osiągnięta zwykle będzie mniejsza od wartości teoretycznej.
* Teraz, dla każdego punktu pomiarowego odniesienia, przeprowadzamy właściwą _punktową serię pomiarową_:
  * dla wartości `X` wyznaczonej w poprzednim kroku dla tego punktu odniesienia realizujemy szereg (np. 10) [pomiarów elementarnych](#pomiar-elementarny-przebieg), po każdym z nich zapisując jego wyniki cząstkowe jako wartości następujących metryk: **(1)** liczba pakietów faktycznie wygenerowanych równa $(Total{\_}packets + Packets{\_}dropped) / 1000$, **(1)** strata pakietów jako wartość pola _Packets dropped_ w logu, **(1)** średnie opóźnienie pakietu jako wartość pola _Average delay_ w logu
  * po wykonaniu wszystkich pomiarów elementarnych w ramach punktowej serii pomiarowej uśredniamy wartość każdej z wymienionych metryk. Przy sporządzaniu wykresów średniówki opóźnienia i strat pakietów powinny znaleźć się w punkcie o współrzędnej na osi odciętej równej wartości średniej wyrażenia $(Total{\_}packets + Packets{\_}dropped) / 1000$ (chociaż punkt odniesienia wskazuje na teoretyczną szybkość generowania pakietów równą `X`).
* Po zrealizowaniu wszystkich _punktowych serii pomiarowych_ dla danego typu strumienia pakietów sporządzamy odpowiednie wykresy (dla strat pakietów i dla opóźnienia). Tym kończymy daną punktową serię pomiarową.
* Następnie albo przechodzimy do realizacji _serii pomiarów_ dla kolejnego niezbadanego jeszcze typu strumienia, albo kończymy pomiary i przechodzimy do analizy wyników i sporządzania wniosków.

## Raport: wyniki i wnioski

W raporcie należy przedstawić w formie graficznej charakterystryki opóźnieniowe i strat pakietów (po uśrednieniu z pomiarów elementarnych) dla poszczególnych (trzech) badanych rodzajów ruchu. Charakterystyka powinna przedstawiać zależność (uśrednionej) wartości danej metryki (opóźnienie, strata pakietów) względem <u>uzyskanej szybkości</u> napływu (generowania przez `ITGSend`) pakietów. Oczywiście - jak już wspomniano wcześniej - _uzyskana szybkość_ napływu pakietów powinna być wartością średnią z wielu (np. 10) przebiegów elementarnych przeprowadzonych dla danego zestawu parametrów strumienia pakietów.

Na podstawie przedstawionych charakterystyk należy wzajemnie porównać pomiary i **przedstawić syntetyczne wnioski płynące z ćwiczenia**.

Uwaga: wnioski mają zawierać własne przemyślenia, refleksje, podsumowania zdobytej wiedzy/umiejętności, a także mogą zawierać uwagi odnośnie do stopnia złożoności/formy laboratorium, sugestie na przyszłość, etc. Natomiast do wniosków nie zalicza się streszczenia przebiegu ćwiczenia (skuteczność działań widać na podstawie przedstawionych charakterystyk) czy listy zrealizowanych pomiarów (wiem na podstawie wyników jakie one były). Można oczywiście skomentować napotkane problemy, sposoby ich pokonania czy zastosowane niestandardowe zabiegi.

W przypadku realizacji **zadania bonusowego** należy wyraźnie zaznaczyć fakt jego podjęcia i wskazać miejsce opisania (najlepiej anonsować to na początku raportu).

# DODATEK: optymalizacja wydajnościowa pomiarów

Generacja ruchu pakietowego o zadanych własnościach statystycznych nie jest trywialna w aspekcie wydajnościowym. Powodem jest konieczność wysyłania kolejnych pakietów w odstępach czasowych, które są generowane zgodnie z założonym dla danego strumienia procesem stochastycznym, utrzymując jednocześnie dużą szybkość generowania pakietów (np. emulując ruch mający dobrze dociążyć łącze 1GBit/s należy generować ok. 100 tys. pakietów na sekundę). Dla typowego sprzętu "domowego", zwłaszcza korzystając z wirtualizowanych środowisk, może to być wyzwanie ponad miarę. Jast tak w szczególności w przypadku wykorzystywania aplikacji D-ITG. Z tego powodu staramy się zoptymalizować systemowe ustawienia aplikacji - zwłaszcza strony nadawczej `ITGSend` - pod kątem wydajnościowym. Pomimo tego nie udaje się uzyskać idealnych warunków pracy generatora. Dotyczy to w szczególności rozbieżności pomiędzy zakładaną (teoretyczną) a faktycznie osiągniętą w założonym czasie liczbą wygenerowanych pakietów. Dlatego wnioski należy ostatecznie "kalibrować" względem wartości faktycznie uzyskanych, a nie teoretycznie wynikających z przyjętych ustawień; o kalibracji więcej napisano w sekcji [Opis zadań do wykonania](#opis-zadań-do-wykonania).

  ## Maszyna goszcząca i maszyna wirtualna

  Zalecane jest wyłączenie zbędnych aplikacji w maszynie goszczącej, które okresowo "zjadają" zasoby CPU. W szczególności dotyczy to przeglądarek. Niestety, przynajmniej w Windows, nie da się zmienić priorytetu procesów danej VM dla nadzorcy VirtualBox. Pewne sposoby podwyższania priorytetu VM są dostępne w Hyper-V, ale (pomijając nawet kwestię innego obrazu) nie jest to trywialne i rezygnujemy z tego zabiegu w naszym przypadku.

  ## Moduł odbiorczy `ITGRecv`

Moduł ten jest uruchamiany z domyślnym dla Linuksa priorytetem procesu (parametr `nice` równy zero, niczego nie trzeba specyfikować w linii komendy - porównaj skrypt `lbr.sh`).

  ## Moduł nadawczy `ITGSend`

Moduł nadawczy jest uruchamiany z możliwie wysokim priorytetem procesu (parametr `chrt --fifo 1` w linii komendy - por. skrypt `lbr.sh`). Dodatkowo, zgodnie z podanym wcześniej opisem (i komentarzem w manualu D-ITG) dotyczącym opcji `-j 1`, można zrezygnować z generowania logów po stronie nadawczej (w naszej komendzie uruchamiajacej nadawcę `ITGSend` wystarczy usunąć opcję `-l sender.log`).
