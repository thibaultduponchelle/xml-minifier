use strict;
use warnings;

use Test::More 0.98;

use XML::Minify qw(minify);


# Actually we test that the processing of entities which is a feature implemeted by xmlprocessor (XML::LibXML) is preserved by our minifier


my $maxi = << "END";
<root> Not empty <![CDATA[ mytext ]]> <keepblanks> </keepblanks> <![CDATA[ mytext ]]> </root>
END

my $minikeepcdata = << "END"; 
<root> Not empty <![CDATA[ mytext ]]> <keepblanks> </keepblanks> <![CDATA[ mytext ]]> </root>
END

my $minidropcdata = << "END"; 
<root> Not empty  <keepblanks> </keepblanks></root>
END

chomp $maxi;
chomp $minikeepcdata;
chomp $minidropcdata;

is(minify($maxi, no_prolog => 1, keep_cdata => 1), $minikeepcdata, "Keep cdata, nothing can be done");
is(minify($maxi, no_prolog => 1, keep_cdata => 0), $minidropcdata, "Remove cdata therefore can clean some blanks");

done_testing;
