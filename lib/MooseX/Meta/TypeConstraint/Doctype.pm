package MooseX::Meta::TypeConstraint::Doctype;
use Moose;

use Devel::PartialDump 'dump';
use Moose::Util::TypeConstraints qw(class_type find_type_constraint
                                    match_on_type);
use Scalar::Util 'weaken';

use MooseX::Validation::Doctypes::Errors;

extends 'Moose::Meta::TypeConstraint';

class_type('Moose::Meta::TypeConstraint');

has doctype => (
    is       => 'ro',
    isa      => 'Ref',
    required => 1,
);

has '+parent' => (
    default => sub { find_type_constraint('Ref') },
);

has '+constraint' => (
    lazy    => 1,
    default => sub {
        weaken(my $self = shift);
        return sub { !$self->validate_doctype($_) };
    },
);

has '+message' => (
    default => sub {
        weaken(my $self = shift);
        return sub { $self->validate_doctype($_) };
    },
);

sub validate_doctype {
    my $self = shift;
    my ($data, $doctype, $prefix) = @_;

    $doctype = $self->doctype
        unless defined $doctype;
    $prefix = ''
        unless defined $prefix;

    my ($errors, $extra_data);

    match_on_type $doctype => (
        'HashRef' => sub {
            if (!find_type_constraint('HashRef')->check($data)) {
                $errors = $data;
            }
            else {
                for my $key (keys %$doctype) {
                    my $sub_errors = $self->validate_doctype(
                        $data->{$key},
                        $doctype->{$key},
                        join('.', (length($prefix) ? $prefix : ()), $key)
                    );
                    if ($sub_errors) {
                        if ($sub_errors->has_errors) {
                            $errors ||= {};
                            $errors->{$key} = $sub_errors->errors;
                        }
                        if ($sub_errors->has_extra_data) {
                            $extra_data ||= {};
                            $extra_data->{$key} = $sub_errors->extra_data;
                        }
                    }
                }
                for my $key (keys %$data) {
                    if (!exists $doctype->{$key}) {
                        $extra_data ||= {};
                        $extra_data->{$key} = $data->{$key};
                    }
                }
            }
        },
        'ArrayRef' => sub {
            if (!find_type_constraint('ArrayRef')->check($data)) {
                $errors = $data;
            }
            else {
                for my $i (0..$#$doctype) {
                    my $sub_errors = $self->validate_doctype(
                        $data->[$i],
                        $doctype->[$i],
                        join('.', (length($prefix) ? $prefix : ()), "[$i]")
                    );
                    if ($sub_errors) {
                        if ($sub_errors->has_errors) {
                            $errors ||= [];
                            $errors->[$i] = $sub_errors->errors;
                        }
                        if ($sub_errors->has_extra_data) {
                            $extra_data ||= [];
                            $extra_data->[$i] = $sub_errors->extra_data;
                        }
                    }
                }
                for my $i (0..$#$data) {
                    next if $i < @$doctype;
                    $extra_data ||= [];
                    $extra_data->[$i] = $data->[$i];
                }
            }
        },
        'Str|Moose::Meta::TypeConstraint' => sub {
            my $tc = Moose::Util::TypeConstraints::find_or_parse_type_constraint($doctype);
            die "Unknown type $doctype" unless $tc;
            if (!$tc->check($data)) {
                $errors = "invalid value " . dump($data) . " for '$prefix'";
            }
        },
        => sub {
            die "Unknown doctype at position '$prefix': " . dump($doctype);
        },
    );

    return unless $errors || $extra_data;

    return MooseX::Validation::Doctypes::Errors->new(
        ($errors     ? (errors     => $errors)     : ()),
        ($extra_data ? (extra_data => $extra_data) : ()),
    );
}

no Moose;

1;