#!/bin/bash

ip netns delete h1
ip netns delete h2
ip link delete s1-h1
ip link delete s1-h2
#ovs-vsctl del-br s1
ip link delete s1

echo "Siec usunieto."
