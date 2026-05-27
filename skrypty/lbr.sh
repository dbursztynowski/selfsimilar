#!/bin/bash

#*****************************************************************
#**********************  OPIS I INFO POMOCNICZE ******************
#*****************************************************************

# UWAGA: Wszystkie komendy podane w tej sekcji sluza tylo celom ilustracyjnym,
# nie sa do "odkomentowania".

# Ref.
#  https://oneuptime.com/blog/post/2026-03-20-create-veth-pair-ip-link-type-veth/view
#  https://oneuptime.com/blog/post/2026-03-02-how-to-use-tc-traffic-control-for-bandwidth-limiting-on-ubuntu/view

#----------------------------------------------------------------
#==================
# Maszyna wirtualna
#==================
# Ustawiamy parametry UDP odpowiadajace duzemu ruchowi
# https://docs.byteplus.com/en/docs/ecs/Adjust_the_net_ipv4_udp_mem
#nano /etc/sysctl.conf
# - dodaj: ustawienie limitow na calkowita pamiec dla soketoww UDP
#net.ipv4.udp_mem = 196608 262144 524288   <===  odpowiada 0.75GB, 1GB, 2GB
#sudo sysctl -p

#===================================
# GENERATOR RUCHU - ROZNE INFORMACJE
#===================================

# Wykorzystujemy generator ruchu pakietowego D-ITG w wersji 2.8.1
# https://traffic.comics.unina.it/software/ITG

#Obecne wzorcowe
# (maszyna goszczaca: Windows 11, procesor Intel(R) Core(TM) i7-8850H CPU @ 2.60GHz, 2592 MHz, Rdzenie: 6, Procesory logiczne: 12)

# parametry dla generatora D-ITG
# -T - rodzaj protokolu transmisyjnego do wykorzystania
# -a - adres strony odbiorczej
# -t - czas trwania przebiegu (symulacji)
# -c - dugosc pakietu (byte)
# -C - proces nalpywu pakietow ma byc typu "constant packet rate" z okreslona przeplywnoscia w pakietach/sekunde
# -E - proces naplywu pakietow ma miec rozklad wykladniczy z przeplywnoscia okreslona w pakietach/sekunde
# -O - proces naplywu pakietow ma miec rozklad Poissona z przeplywnoscia okreslona w pakietach/sekunde
# -W <k> <lambda> - proces naplywu pakietow ma miec rozklad Weibulla z parametrami k oraz lambda (lambda podane w milisekundach)
#    - o zasadnosci uzycia rozkladu Weibulla w modelowaniu ruchu w Internecie: https://www.sciencedirect.com/science/article/abs/pii/S1084804519301547
# -j 1 - strona nadawcza D-ITG stara sie zachowac wymagana przeplywnosc wysylajac zalegle pakiety po przebudzeniu (por. D-ITG user guide)
# -l - nazwa pliku z logiem strony nadawczej
# -x - nazwa pliku z logiem strony odbiorczej

# parametry dla interfejsow
# - rate - przeplywnosc lacza
# - limit - dlugosc bufora nadawczego

# ustawienie przeplywnosci lacza (rate) i dlugosci bufora nadawczego (limit) dla interfejsu s1-h2
#sudo tc qdisc change dev s1-h2 root netem rate 1.2mbit limit 110

# --- Uruchomienie odbiornika (receiver) z priorytetem 19 (wysoki)
# sudo nice -n -19 /usr/bin/ITGRecv

# --- Uruchomienie nadawcy z priorytetem 19 (wysoki)
#sudo nice -n -19 /usr/bin/ITGSend -T UDP -a 10.0.0.2 -c 1200 -C 100 -t 20000 -l sender.log -x receiver.log

# odczytaj log po zakonczeniu przebiegu (wyjscie na terminal)
#/usr/bin/ITGDec <log-filename>
#/usr/bin/ITGDec sender.log


#---------------------------------------------------------------
#===================================
# Schemat pomiaru elementarnego
# ==================================
#
# Generator ruchu ITGSend, odbiornik ITGRecv.
#
# Wezel h1 (sieciowa przestrzen nazw) reprezentuje ruter wysylajacy pakiety interfejsem h1-s1 do
# rutera h2. Generator ITGSend reprezentuje zbiorczy ruch w tym ruterze kierowany na interfejs
# h1-s1 (do rutera h). Ujsciem dla tego ruchu jest odbiornik ITGRecv w wezle h2. Ruch przechodzi
# przez switch s1. Obserwujemy efekty opoznieniowe dla ruchu wychodzacego ze switcha s1 interfejsem
# s1-h2 do h2.
#
# W ramach konfiguracji tego srodowiska, eksperymentalnie dostrajamy parametry transmisyjne (przepustowosc,
# dlugosc bufora) interfejsu s1-h2 tak, aby wyniki pomiaru nie byly odksztalcane przez
# narzut obliczeniowy samego generatora ITGSens - tak aby mozliwie dobrze uchwycic efekty kolejkowe dla
# roznych charakterystyk ruchowych strumienia pakietow na obserwowanym interfejsie. Pozostale interfejsy
# konfigurujemy tak, aby nie odksztalcaly one charakterystyki ruchu pakietowego (brak strat, mozliwie
# zerowe opoznienia).
#
#       ┌───────────────────┐              ┌───────────────────┐
#       │        h1         │              │        h2         │
#       │    ┌─────────┐    │              │    ┌─────────┐    │
#       │    │ ITGSend │    │              │    │ ITGRecv │    │
#       │    └────┬────┘    │              │    └────┬────┘    │
#       │     UDP V         │              │     UDP Λ         │
#       │    ┌────┴────┐    │              │    ┌────┴────┐    │
#       │    │  h1-s1  │10.0.0.1           │    │  h2-s1  │10.0.0.2
#       └────└────┬────┘────┘              └────└────┬────┘────┘
#                 │                                  │
#       ┌────┌────┴────┐────────────────────────┌────┴────┐────┐
#       │    │  s1-h1  │                        │  s1-h2  │    │
#       │    └─────────┘                        └─────────┘    │
#       │                          s1                          │
#       │                                                      │
#       └──────────────────────────────────────────────────────┘
#
#-----------------------------------------------------------------

#********************************************************************
#*************************  CZESC WYKONAWCZA ************************
#********************************************************************
# Czesc wykonawcza obejmuje dwa etapy.

# ETAP 1 etap prowadzi do utworzenia naszej sieci ze zwymiarowanymi
# odpowiednio buforami interfejsow sieciowych(na poczatku zepol
# powinien eksperymentalnie sprawdzic czy nie nalezaloby zmodyfikowac
# rozmiaru bufora s1-h2 w jego srodowisku obliczeniowym).

# ETAP 2 to pomiary elementarne (termin wg instrukcji w Gitlab)
# zorganizowane w pewne sekwencje pomiarowe dla różnych przypadków ruchu.
# Pomiary te są uruchamiane w trybie recznym, po wykonaniu niniejszego
# skryptu, w odrebnym oknie terminala. Wzorcowe komendy dla tewgo etapu
# sluzace do tworzenia strumieni roznych rodzajow sa podane w koncowej
# czesci niniejszego skryptu. Oczywiscie istnieje mozliwosc zanurzenia
# pomiarow w skrypty (Python czy bash, etc.) w celu zautomatyzowania
# całego procesu pomiarowego i obrobki wynikow. Podjęcie takiej
# dodatkowej pracy pozostawiamy zainteresowanym zespolom do
# indywidualnego rozwazenia.

#####################################################################
# ETAP 1: Utworzenie sieci (hosty jako "network namespaces" i switch)
#####################################################################

# Utwórz network namespaces dla hostów; wylistuj namespaces
echo "Utwórz network namespaces dla hostów; wylistuj namespaces"
ip netns add h1
ip netns add h2
ip netns show

# Utwórz nasz switch
#ovs-vsctl add-br s1
echo "Utworz nasz switch"
ip link add s1 type bridge

# Utwórz łącza (VETH pairs); wylistuj łącza
echo "twórz łącza (VETH pairs); wylistuj łącza"
ip link add h1-s1 type veth peer name s1-h1
ip link add h2-s1 type veth peer name s1-h2
ip link show

# Dołącz porty hostów do naszych net-namespaces
echo  "Dołącz porty hostów do naszych net-namespaces"
ip link set h1-s1 netns h1
ip link set h2-s1 netns h2
ip netns exec h1 ip link show
ip netns exec h2 ip link show

#" --- Dołącz porty par veth do naszego switcha"
# wariant OVS
#ovs-vsctl add-port s1 s1-h1
#ovs-vsctl add-port s1 s1-h2
#ovs-vsctl show

# wariant linux bridge
echo "Dołącz porty par veth do naszego switcha"
ip link set s1-h1 master s1
ip link set s1-h2 master s1

# Skonfiguruj adresy i postaw urzadzenia
echo "Skonfiguruj adresy i postaw urzadzenia"
ip netns exec h1 ip addr add 10.0.0.1/24 dev h1-s1
ip netns exec h1 ip link set h1-s1 up
ip netns exec h2 ip addr add 10.0.0.2/24 dev h2-s1
ip netns exec h2 ip link set h2-s1 up
ip link set s1 up
ip link set s1-h1 up
ip link set s1-h2 up

#==============================================
# Skonfiguruj bufory nadawcze interfejsow"
#==============================================

# - z wyjatkiem interfejsu s1-h2, ustawiamy bufory duze (50000 pakietow) - male straty
# w istocie, zwazywszy na niskie przepywnosci lacza s1-h2 ustawiane dalej komenda tc, ponizsze
# wartosci sa znacznie wieksze niz potrzeba, ale ...
ip netns exec h1 ip link set dev h1-s1 txqueuelen 50000
ip netns exec h2 ip link set dev h2-s1 txqueuelen 50000
ip link set dev s1-h1 txqueuelen 50000

# - bufor s1-h2 regulowany dla ruchu do h2
# rozmiar [pakiety]
ip link set dev s1-h2 txqueuelen 50000  # w istocie wartosc standardowa, ale ...; powinno byc >> od ograniczenia limit w tbf lub netem

# qdisc netem dla ustalenia przeplywnosci lacza i dlugosci bufora [pakiety]
tc qdisc add dev s1-h2 root netem rate 1.2mbit limit 10
# uwaga: kolejna zmiana parametrow "z reki": uzyc "change" zamiast "add" w komendzie podanej powyzej
# check current settings in other terminal
# tc -s qdisc ls dev eth0

# --- Sprawdź drożność sieci
ip netns exec h1 ping -c1 10.0.0.2

# --- Zablokuj uzywanie IPv6
#ip netns exec h1 sysctl -w net.ipv6.conf.all.disable_ipv6=1
#ip netns exec h1 sysctl -w net.ipv6.conf.default.disable_ipv6=1
#ip netns exec h1 sysctl -w net.ipv6.conf.lo.disable_ipv6=1
#ip netns exec h2 sysctl -w net.ipv6.conf.all.disable_ipv6=1
#ip netns exec h2 sysctl -w net.ipv6.conf.default.disable_ipv6=1
#ip netns exec h2 sysctl -w net.ipv6.conf.lo.disable_ipv6=1

#==============================================
# Wystartuj pomiary
#==============================================

# --- Start odbiornik na h2. Nadajnik (start przeplyw na h1 -- ponizej) nalezy uruchomic
# recznie kiedy juz dziala odbiornik.
# obecnie odbiornik D-ITG startujemy na domyslnym priorytecie, aby nie rywalizowal z nadajnikiem

ip netns exec h2 /usr/bin/ITGRecv
#ip netns exec h2 nice -n -19 /usr/bin/ITGRecv

# >>> tutaj niniejszy skrypt konczy swoje dzialanie;
# >>> ponizsze komendy wykonujemy juz recznie, w odrebnym oknie terminala, jako - wg instrukcji z Gitlab - "pomiary elementarne"

###############################################
# ETAP 2: Eksperymenty elementarne
###############################################

# Nadajnik startujemy recznie, w odrebnym oknie terminala

##" --- Start przeplyw na h1 - w odrebnym oknie terminala"
# stosujemy opcje chrt --fifo 1, ktora przyznaje nadajnikowo mozliwie wysoki priorytet

# UWAGA: w docelowych przebiegach mozna zrezygnowac z generowania logu nadawcy, co troche poprawia jakosc wynikow.
# Calkowita, faktycznie osiagnieta szybkosc nadawania pakietow latwo uzyskac z logu odbiornika jako sume wartosci
# pol "Total packets" i "Packets dropped" (zawsze jest on rowna wartosci pola "Total packets" w logu
# nadajnika -  dla pewnosci mozna to sprawdzic osobiscie na wstepie).
# Ponizej korzystamy z dyrektywy "chrt" pozwalajacej nadac procesowi wyzszy priorytet niz osiagalny dyrektywa "nice",
#   jednak dla kompletu podajemy tez wersje z "nice".

# naplyw: costant packet rate
#sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 100 -t 15000 -j 1 -l sender.log -x receiver.log
##sudo ip netns exec h1  nice -n -19 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 100 -t 15000 -j 1 -l sender.log -x receiver.log

# naplyw: proces Poissona
#sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -O 100 -t 15000 -j 1 -l sender.log -x receiver.log
##sudo ip netns exec h1 nice -n -19  /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -O 100 -t 15000 -j 1 -l sender.log -x receiver.log

# naplyw: proces o rozkladzie Weibulla (podane parametry 0.5, 50 teoretycznie odpowiadaja sredniej intensywnosci 100pak/sek)
#sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -W 0.5 50 -t 15000 -j 1 -l sender.log -x receiver.log
##sudo ip netns exec h1  nice -n -19 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -W 0.5 50 -t 15000 -j 1 -l sender.log -x receiver.log

# naplyw: typ zrodla ON/OFF ze stalym czasem w stanie ON o wartosci 200 ms i stalym czasem w stanie OFF o wartosci 800 ms, i o stalej szybkosci
#   nadawania w stanie ON rownej 100 pakietow/sek
#sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 100 -t 15000 -j 1 -l sender.log -x receiver.log -B C 200 C 800
##sudo ip netns exec h1  nice -n -19 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 100 -t 15000 -j 1 -l sender.log -x receiver.log -B C 200 C 800

# naplyw: jeszcze bardziej nieregularny ruch typu ON/OFF z czasem ON o rozkladzie wykadniczym o sredniej 100ms i czasem OFF o rozkladzie Weibulla o
#   sredniej 100*Gamma(1+1/10) ms, i o stalej szybkosci nadawania w stanie ON rownej 100 pakietow/sek
#sudo ip netns exec h1 chrt --fifo 1 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 100 -t 15000 -j 1 -l sender.log -x receiver.log -B E 100 W 10 100
##sudo ip netns exec h1  nice -n -19 /usr/bin/ITGSend -a 10.0.0.2 -T UDP -c 1200 -C 100 -t 15000 -j 1 -l sender.log -x receiver.log -B E 100 W 10 100

#==============================================
# Odczyt wynikow
#==============================================

# odczytaj log odpowiednim modulem D-ITG - tresc
#   jest kierowana na terminal

#/usr/bin/ITGDec <log-filename>
#/usr/bin/ITGDec sender.log
