#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo <h1>hi from webb : $(hostname -i)</h1> > /var/www/html/index.html

# This is the sample file given in it
# hi djqwh