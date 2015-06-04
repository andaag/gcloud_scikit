#!/bin/bash
IP=$(gcloud compute instances list | grep scikit | awk '{ print $5 }')