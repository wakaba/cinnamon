package Cinnamon::DSL::Capistrano::Filter;
use strict;
use warnings;
no warnings 'redefine';
use Filter::Simple;
use Encode;

FILTER_ONLY
    executable => sub {
        # Use default user name
        s/\bENV\['SSHNAME'\]\s*\|\|\s*\`whoami\`\.chomp/q{PERLDO { my $v = get('input_user'); defined $v ? $v : '' }}/ge;
        s/\`whoami\`\.chomp/q{PERLDO { my $v = get('input_user'); defined $v ? $v : '' }}/ge;

        # role :foo, *hoge("fuga") << {
        #   ...
        # }
        s/\brole\s*\*\[([^\[\]]+)\]/role $1/g;
        s/^(\s*role)\s*\*\[(.+)\]\s*$/$1 $2/gm;
        s/^(\s*role\s*\S+)\s*,\s*\*(.*?)<</$1, sub { $2 },/gm;
        s/^(\s*role\s*\S+)\s*,\s*\*(.*?)$/$1, sub { $2 }/gm;
        s/\broles\[([^\[\]]+)\]\s*=\s*roles\[([^\[\]]+)\]/+Cinnamon::DSL::Capistrano->set_role_alias($1, $2)/g;
        s{\bif\s*(\S+)\s+(\S+)\s+(\S+)\s+then}{if ($1 @{[{'==' => 'eq'}->{$2} || $2]} $3) \{}g;
        s{\belsif\s*(\S+)\s+(\S+)\s+(\S+)\s+then}{\} elsif ($1 @{[{'==' => 'eq'}->{$2} || $2]} $3) \{}g;
        s/%Q\b/qq/g;
        s/%q\b/q/g;
    },
    code_no_comments => sub {
        s/(::)|:(\w+)/$1 || qq<'$2'>/ge;
        s/\bdo\b/, sub {/g;
        s/\bPERLDO\b/do/g;
        s/\bend\b/}/g;
        s/\btrue\b/1/g;
        s/\bfalse\b/0/g;
        my %declared;
        s/^(\s*)(\w+)(\s*=\s*)/$1@{[ $declared{$2} ? '' : do { $declared{$2} = 1; 'my ' } ]}\$$2$3/gm;
        s/^(\s*)(\w+)\s*\.\s*chomp\!\s*$/$1chomp $2/gm;
        s/($Filter::Simple::placeholder)\.chomp/+Cinnamon::DSL::Capistrano->chomp\($1\)/g;
        s/\b(@{[join '|', map { quotemeta } keys %declared]})\b/\$$1/g
            if keys %declared;
        s/my \$\$/my \$/g;
        s{\b(\w+(?:\.\w+)+)\b}{my $v = $1; $v =~ tr/\./:/; "call('$v', \@_)"}ge;
        s{^\s*(\w+)\s*$}{my $v = $1; $v =~ tr/\./:/; "call('$v', \@_)"}gem;

        my $prev = '';
        my $line = '';
        my @value;
        for my $v (split /($Filter::Simple::placeholder)|(\x0D?\x0A)/, $_) {
            next if not defined $v or not length $v;
            if ($v =~ /^$Filter::Simple::placeholder$/) {
                $prev = $;;
                $line .= $;;
                push @value, $v;
            } elsif ($prev eq $;) {
                $prev = "$;-inner";
            } elsif ($v =~ /\x0A/) {
                if ($prev ne "\x0A" &&
                    length $prev &&
                    $prev !~ /[{\[,]\s*$/) {
                    if ($line =~ /^\s*(?>[\w']|$;)+\s*=>\s*(?>[\w']|$;)+\s*$/) {
                        $line = '';
                        $prev = "\x0A";
                        push @value, "," . $v;
                    } else {
                        $line = '';
                        $prev = "\x0A";
                        push @value, ";" . $v;
                    }
                } else {
                    $line = '';
                    $prev = "\x0A";
                    push @value, $v;
                }
            } else {
                $line .= $v;
                $prev = $v;
                push @value, $v;
            }
        }
        $_ = join '', @value;
    },
    quotelike => sub {
        s/\@/\\@/g;
        s/#\{getuname\}/\@{[getuname]}/g;
        s/#\{(\w+)\}/\@{[get '$1']}/g;
        s/#\{ENV\['ROLES'\]\}/\@{[get 'role']}/g;
        s/#\{ENV\[([^\[\]]+)\]\}/\$ENV{$1}/g;
    },
    all => sub {
        $_ = decode 'utf-8', $_;
        s/,(\s+#.+);$/,$1/gm;
        s/(\s+#.+);$/;$1/gm;
    };

my $orig_import = \&import;
*import = sub { };

sub convert {
    my (undef, @line) = @_;
    my $filter;
    local *Filter::Simple::filter_read = sub {
        if (@line) {
            $_ .= shift @line;
            return 1;
        } else {
            return 0;
        }
    };
    local *Filter::Simple::filter_add = sub {
        $filter = $_[0];
    };
    
    $orig_import->();

    local $_ = '';
    $filter->();
    return $_;
}

sub convert_and_run {
    my $self = shift;
    my $args = shift;
    local $Cinnamon::DSL::Capistrano::BaseFileName
        = defined $args->{base_file_name} ? $args->{base_file_name} : $args->{file_name}; # or undef
    my $converted = $self->convert(@_);
    
    if ($ENV{CINNAMON_CAP_DEBUG}) {
        my $i = 0;
        print STDERR "Converted script:\n";
        print STDERR join "\n", map { ++$i . ' ' . $_ } split /\n/, $converted;
        print STDERR "\n";
    }

    my $file_name = $args->{file_name} || '(Converted from cap recipe)';
    my $line = $args->{line} || 1;

    eval qq{
        package Cinnamon::DSL::Capistrano::Filter::converted;
        use strict;
        use warnings;
        use Cinnamon::DSL::Capistrano;
#line 1 "$file_name"
        $converted;
        1;
    } or die $@;
}

1;
