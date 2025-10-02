using System.Collections.Generic;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.AspNetCore.Mvc;


namespace MvcMusicStore.Models
{
    [Table("orders", Schema = "mvcmusicstore_mvcmusicstore_dbo")]
    [Bind]
    public partial class Order
    {
        [ScaffoldColumn(false)]
        [Key]
        [Column("orderid")]
        public int OrderId { get; set; }

        [ScaffoldColumn(false)]
        public System.DateTime OrderDate { get; set; }

        [ScaffoldColumn(false)]
        [Column("username")]
        public string Username { get; set; }

        [Required(ErrorMessage = "First Name is required")]
        [DisplayName("First Name")]
        [StringLength(160)]
        [Column("firstname")]
        public string FirstName { get; set; }

        [Required(ErrorMessage = "Last Name is required")]
        [DisplayName("Last Name")]
        [StringLength(160)]
        [Column("lastname")]
        public string LastName { get; set; }

        [Required(ErrorMessage = "Address is required")]
        [StringLength(70)]
        [Column("address")]
        public string Address { get; set; }

        [Required(ErrorMessage = "City is required")]
        [StringLength(40)]
        [Column("city")]
        public string City { get; set; }

        [Required(ErrorMessage = "State is required")]
        [StringLength(40)]
        [Column("state")]
        public string State { get; set; }

        [Required(ErrorMessage = "Postal Code is required")]
        [DisplayName("Postal Code")]
        [StringLength(10)]
        [Column("postalcode")]
        public string PostalCode { get; set; }

        [Required(ErrorMessage = "Country is required")]
        [StringLength(40)]
        [Column("country")]
        public string Country { get; set; }

        [Required(ErrorMessage = "Phone is required")]
        [StringLength(24)]
        [Column("phone")]
        public string Phone { get; set; }

        [Required(ErrorMessage = "Email Address is required")]
        [DisplayName("Email Address")]
        [RegularExpression(@"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}",
            ErrorMessage = "Email is is not valid.")]
        [DataType(DataType.EmailAddress)]
        public string Email { get; set; }

        [ScaffoldColumn(false)]
        [Column("total")]
        public decimal Total { get; set; }

        public List<OrderDetail> OrderDetails { get; set; }
    }
}