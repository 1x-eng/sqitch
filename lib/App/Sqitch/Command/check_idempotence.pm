package App::Sqitch::Command::check_idempotence;

use 5.010;
use strict;
use warnings;
use utf8;
use Locale::TextDomain qw(App-Sqitch);
use App::Sqitch::X qw(hurl);
use Moo;
use App::Sqitch::Types qw(Str);
use SQL::Translator;
use File::Slurp qw(read_file);
use Types::Standard qw(HashRef);

extends 'App::Sqitch::Command';
with 'App::Sqitch::Role::ContextCommand';
with 'App::Sqitch::Role::ConnectingCommand';

# VERSION

has namespace => (
    is  => 'ro',
    isa => Str,
    required => 1,
);

sub options {
    return qw(
        namespace|n=s
    );
}

sub configure {
    my ( $class, $config, $opt ) = @_;

    # Process options here
    if (my $ns = $opt->{namespace}) {
        $opt->{namespace} = $ns;
    } else {
        hurl check_idempotence => __ 'Option "--namespace" is required';
    }

    # Check if database is PostgreSQL
    my $engine = $class->engine_from_options($config, $opt);
    my $dbh    = $engine->dbh;
    hurl check_idempotence => __ 'This command is only available for PostgreSQL' unless $dbh->{Driver}->{Name} eq 'Pg';

    return $opt;
}


sub execute {
    my ( $self, $sqitch ) = @_;

    # Traverse the deploy, and revert directories and check for idempotent SQL statements
    $self->check_idempotent_sql($sqitch, $self->{namespace});
}

my @idempotent_patterns = (
    qr/CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS/i,
    qr/CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS/i,
    qr/ALTER\s+TABLE\s+\w+\s+ADD\s+COLUMN\s+IF\s+NOT\s+EXISTS/i,
    qr/CREATE\s+SEQUENCE\s+IF\s+NOT\s+EXISTS/i,
    qr/CREATE\s+OR\s+REPLACE\s+(?:VIEW|FUNCTION|PROCEDURE|TRIGGER|AGGREGATE|OPERATOR|RULE|POLICY|EVENT\s+TRIGGER|LANGUAGE|EXTENSION)/i,
    qr/CREATE\s+(?:ROLE|USER|SCHEMA|DOMAIN|CAST|COLLATION|CONVERSION|TYPE|SERVER|FOREIGN\s+TABLE|MATERIALIZED\s+VIEW|PUBLICATION|SUBSCRIPTION)\s+IF\s+NOT\s+EXISTS/i,
    qr/CREATE\s+TEXT\s+SEARCH\s+(?:DICTIONARY|CONFIGURATION|PARSER|TEMPLATE)\s+IF\s+NOT\s+EXISTS/i,
);

my @revert_idempotent_patterns = (
    qr/DROP\s+TABLE\s+IF\s+EXISTS/i,
    qr/DROP\s+(?:UNIQUE\s+)?INDEX\s+IF\s+EXISTS/i,
    qr/ALTER\s+TABLE\s+\w+\s+DROP\s+COLUMN\s+IF\s+EXISTS/i,
    qr/DROP\s+SEQUENCE\s+IF\s+EXISTS/i,
    qr/DROP\s+(?:VIEW|FUNCTION|PROCEDURE|TRIGGER|AGGREGATE|OPERATOR|RULE|POLICY|EVENT\s+TRIGGER|LANGUAGE|EXTENSION)\s+IF\s+EXISTS/i,
    qr/DROP\s+(?:ROLE|USER|SCHEMA|DOMAIN|CAST|COLLATION|CONVERSION|TYPE|SERVER|FOREIGN\s+TABLE|MATERIALIZED\s+VIEW|PUBLICATION|SUBSCRIPTION)\s+IF\s+EXISTS/i,
    qr/DROP\s+TEXT\s+SEARCH\s+(?:DICTIONARY|CONFIGURATION|PARSER|TEMPLATE)\s+IF\s+EXISTS/i,
);

sub check_idempotent_sql {
    my ($self, $sqitch, $namespace) = @_;
    my $engine = $sqitch->engine;
    my $dir = $engine->plan->dir;
    
    my $deploy_dir = $dir->subdir('deploy');
    my $revert_dir = $dir->subdir('revert');

    my %patterns = (
        deploy => \@idempotent_patterns,
        revert => \@revert_idempotent_patterns,
    );

    for my $subdir_name (qw(deploy revert)) {
        my $subdir = $dir->subdir($subdir_name);
        my $script = $subdir->file("$namespace.sql");
        if (-e $script) {
            my $content = read_file($script->stringify);
            my @statements = split(/;/, $content);
            my $is_idempotent = 1;

            my $translator = SQL::Translator->new(
                from => 'PostgreSQL',
                to   => 'PostgreSQL',
            );

            my $pattern_list = $patterns{$subdir_name} // \@idempotent_patterns;
            for my $statement (@statements) {
                if (!is_idempotent($translator, $statement, $pattern_list)) {
                    $is_idempotent = 0;
                    print "Non-idempotent statement found in $script:\n$statement\n\n";
                }
            }

            if ($is_idempotent) {
                print "All SQL statements in the script $script are idempotent.\n";
            } else {
                print "Some SQL statements in the script $script are not idempotent.\n";
            }
        }
    }
}

sub is_idempotent {
    my ($translator, $query, $pattern_list) = @_;
    my $data = $translator->translate(\$query);

    for my $pattern (@$pattern_list) {
        if ($data =~ $pattern) {
            return 1;
        }
    }

    # Return 0 if no idempotent pattern is found
    return 0;
}

1;


__END__

=head1 Name

App::Sqitch::Command::check_idempotence - Check idempotency of deploy & revert SQL statements in a given sqitch namespace

=head1 Synopsis

  my $cmd = App::Sqitch::Command::check_idempotence->new(%params);
  $cmd->execute;

=head1 Description

This command checks if the deploy & revert SQL statements in the specified namespace are idempotent. 
The namespace corresponds to the SQL files in the deploy, and revert directories.

=head1 Interface

=head2 Class Methods

=head3 C<options>

  my @opts = App::Sqitch::Command::check_idempotence->options;

Returns a list of L<Getopt::Long> option specifications for the command-line options for the C<check_idempotence> command.

=head3 C<configure>

  my $params = App::Sqitch::Command::check_idempotence->configure(
      $config,
      $options,
  );

Processes the configuration and command options and returns a hash suitable for the constructor.

=head2 Instance Methods

=head3 C<execute>

  $check_idempotence->execute;

Executes the check_idempotence command.

=head1 See Also

=over

=item L<sqitch>

The Sqitch command-line client.

=back

=head1 Author

Pruthvi Kumar <itspruthvikumar@gmail.com>

=head1 License

Copyright (c) 2023 Pruthvi Kumar

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

=cut